import Combine
import Foundation

// The sidekick's brain, with everything it needs from the app handed in: what the agents did (the ledger), whether the user is at the computer (presence), the stuck rules, the notes and the show gate,
// the dismissal memory and the ONE one-shot clock. It reads events and labels; it never answers a request, never sends anything and never logs. It touches nothing of the app directly: the app gives
// it the time, the idle seconds, what is in front of the island and so on as closures (`Env`), and takes what it says through two more (`present`, `retract`), so a test drives it with a clock and a timer
// by hand and proves the whole flow (a recap after a lock, a nudge for a loop, a held note, a dropped one, a muted kind) without launching anything. Foundation and Combine only.
//
// The flow, in one line: every input (an event, a signal from the Mac, a tick, the clock, a change of what is in front of the island, a click on a note) updates the memory and then runs `evaluate()`, which
// retires a note whose time is up, drops the held notes whose time is up, asks the stuck rules for a nudge, shows the first note the gate lets through and sets the clock to the nearest deadline.

@MainActor
final class SidekickEngine: ObservableObject {
    /// What the app gives the engine. Every closure has a quiet default, so a test sets only what it uses.
    struct Env {
        /// The sidekick's clock, in ms (wall time: the minutes a Mac slept count as time away).
        var now: () -> Double
        /// Seconds since the user's last input (`PresenceMonitor.idleSeconds`).
        var idleSeconds: () -> Double = { 0 }
        /// "approval" or "question" while a card is in front of the island, else nil.
        var cardInFront: () -> String? = { nil }
        /// The approval card is on screen right now (the waiting nudge is for a request whose card is NOT).
        var ownCardShown: () -> Bool = { false }
        /// The session's (by session ID) stepped-back mark (focus awareness): its time (ms, the engine's clock) at which it lapses (ten minutes), or nil when the session has no live mark. A session with a live mark
        /// still waits in its own app, so its waiting nudge is not for it. The engine wakes at the lapse: a blocked agent sends no event, so nothing else would re-judge its held waiting nudge.
        var stepBackEnd: (String) -> Double? = { _ in nil }
        /// The earliest time (ms, the engine's clock) at which a live stepped-back mark runs out, whatever its session. The app's marks are the source, not the ledger, which evicts sessions. Nil when no mark is live.
        var focusLapseAt: () -> Double? = { nil }
        /// A stepped-back mark has run out: the app redraws what reads the marks (the pill's dot and note), once per lapse, whether or not the Sidekick is on.
        var focusLapsed: () -> Void = {}
        /// The island is hidden or compact, or open on a view that can host a note (`SidekickHost`).
        var canHost: () -> Bool = { true }
        /// The user is typing in the island.
        var typing: () -> Bool = { false }
        /// The view the island is open on (its raw value), or nil while it is hidden or compact. A note that is on screen and finds the island open on another view than its own ("sidekick") has been covered.
        var openView: () -> String? = { nil }
        /// An agent is rate-limited (the cat already shows it).
        var ratelimited: () -> Bool = { false }
        /// The pointer is on the island: a note is kept while it is.
        var pointerOver: () -> Bool = { false }
        /// The note goes on the island. The app opens the island on it, the way a finished task does.
        var present: (SKNote) -> Void = { _ in }
        /// The note leaves the island (answered, or its time is up).
        var retract: (SKNote) -> Void = { _ in }
        /// A nicer sentence for a recap from a model on this computer, or nil (`SidekickVoiceApp`). Never given anything but the note's own words and facts.
        var polish: (SKNote) async -> String? = { _ in nil }
        /// "mac", "windows" or "linux": when the app gave up on a request (`SidekickStuck.giveUpMs`).
        var platform = "mac"
    }

    /// The note on the island now, or nil. The view reads it.
    @Published private(set) var showing: SKNote?

    /// The agents that have a live session (one that has not ended): the cats a drop may hand a path to, and what the chat's chip watches. Written only when the set changes, from every write of the ledger
    /// (an event, an answered card, the pruning), so a view that observes it re-draws exactly when an agent starts or stops and never on a tick.
    @Published private(set) var liveAgents: Set<String> = []

    private(set) var ledger = SKLedger() {
        didSet {
            let live = Set(SidekickLedger.live(ledger).map(\.agentId))
            if live != liveAgents { liveAgents = live }
        }
    }
    private(set) var presence = SKPresence()
    /// The nearest time (ms) a live stepped-back mark runs out (`Env.focusLapseAt`), or nil. `evaluate` sets it, so the clock wakes then and the app is told (`Env.focusLapsed`).
    private var focusLapseAt: Double?
    private(set) var notes = SidekickNotes()
    let store: SidekickStore
    let clock: SidekickClock
    private let env: Env
    private let codex: Bool
    private var nextId = 1
    private var lastIdleSample: Double?
    private var lastHeldCheck: Double?
    /// What the gate was told about the last note shown, to put it back as it was if it is covered before anyone saw it: the time of the note before it.
    private var lastShownBefore: Double?
    /// The view that covered an unseen note: the note waits until the island is open on another one (or folds), and is not shown over the card that took the island from it.
    private var coveredBy: String?
    private var evaluating = false, again = false
    /// The local voice's request for the note on screen, so a test can wait for it.
    private(set) var polishTask: Task<Void, Never>?

    init(store: SidekickStore, clock: SidekickClock, env: Env, codex: Bool = true) {
        self.store = store; self.clock = clock; self.env = env; self.codex = codex
        clock.onFire = { [weak self] in self?.evaluate() }
    }

    // MARK: What it is told

    /// A hook payload at the feed point. An event the ledger does not know is nothing. The idle time is read here too (a hook event is a tick that already exists).
    func feed(payload: [String: Any]) {
        guard let event = SidekickLedger.eventFrom(payload, now: env.now(), codex: codex) else { return }
        ledger = SidekickLedger.apply(ledger, event)
        sampleIdle()
        evaluate()
    }

    /// The user answered an approval card (Deny, Allow or Always): the one event that is not a hook.
    func approvalAnswered(agentId: String, sessionId: String) {
        ledger = SidekickLedger.apply(ledger, SidekickLedger.approvalAnswered(agentId: agentId, sessionId: SidekickLedger.capId(sessionId), now: env.now()))
        evaluate()
    }

    /// The Mac locked, slept, woke and so on (`PresenceMonitor`). A wake re-evaluates at once, because a one-shot timer does not fire while the Mac sleeps.
    func presenceEvent(_ event: SKPresenceFlags.Event) {
        step(event.signal)
        if event == .unlock || event == .wake { sampleIdle() }
        evaluate()
    }

    /// A tick the island already has (its poll). It asks the OS for the idle time only when one is due: at most every 5 s (every second while the user is away by idle), and only while an agent has a live session.
    func tick() {
        let now = env.now()
        // A note the gate is holding (the user was typing, the island was open on something else) is asked again, at most once a second: this is how a change that no deadline marks is noticed.
        if !notes.held.isEmpty, lastHeldCheck.map({ now < $0 || now - $0 >= 1000 }) ?? true { lastHeldCheck = now; evaluate() }
        if let last = lastIdleSample, last <= now, now - last < (presence.reasons.contains("idle") ? SidekickIdle.awayMs : SidekickIdle.normalMs) { return }   // the cheapest check first: this runs on every tick of the island's poll
        guard SidekickIdle.sampleDue(now: now, last: lastIdleSample, liveSessions: !SidekickLedger.live(ledger).isEmpty, idleAway: presence.reasons.contains("idle")) else { return }
        let before = presence
        sampleIdle()
        if presence != before { evaluate() }
    }

    /// Something that decides whether a note may show changed: the view or mode of the island, a card, typing, the pointer, a rate limit or a setting.
    func envChanged() { evaluate() }

    /// Evaluates again for each value `signal` publishes, one main-queue turn later. A `@Published` publishes in `willSet`, before the new value is stored: an evaluation in the same call re-reads the
    /// state through `Env` and finds the OLD one (the card is still `.approval` while the chat opens over it). One turn later the write has landed. No timer, and no coalescing: each published value gets its own main-queue turn, which is one cheap `evaluate()` per distinct view change or settings write.
    func watch<P: Publisher>(_ signal: P) -> AnyCancellable where P.Failure == Never {
        signal.receive(on: DispatchQueue.main).sink { [weak self] _ in MainActor.assumeIsolated { self?.envChanged() } }
    }

    /// The user clicked OK, × or Not now: it counts as a dismissal of the note's kind.
    func dismiss() {
        guard let note = notes.retire() else { return }
        // The note leaves first, and the dismissal is written last: a store observer that calls `envChanged()` re-enters `evaluate()` inside the write, may present a held note, and must find the engine's `showing` in step.
        showing = nil
        env.retract(note)
        store.dismiss(note.kind)
        evaluate()
    }

    /// The user tapped a note's action (Show me): the note goes, and it is not a dismissal.
    func act() -> SKNote? {
        guard let note = notes.retire() else { return nil }
        showing = nil
        env.retract(note)
        evaluate()
        return note
    }

    /// The island is open on the note: the user has seen it.
    func noteSeen() { notes.markSeen() }

    // MARK: What it answers

    /// "What's Claude doing?": the question's answer from the ledger, or nil when `text` is not the status question (it is then a normal chat message).
    func status(for text: String) -> SKLines? {
        let m = SidekickRecap.matchStatusQuestion(text)
        guard m.matched else { return nil }
        return SidekickRecap.status(now: env.now(), sessions: ledger.sessions, agent: m.agentId)
    }

    // MARK: Inside

    private func step(_ signal: SKSignal) {
        let r = SidekickPresence.step(presence, signal, now: env.now())
        presence = r.state
        if let back = r.back, store.settings.on, let recap = SidekickRecap.recap(awaySince: back.awaySince, now: env.now(), sessions: ledger.sessions) {
            notes.offer(SKNote(id: take(), kind: "recap", text: recap.lines.joined(separator: "\n"), facts: recap.facts, awaySince: back.awaySince, createdAt: env.now()), now: env.now())
        }
    }

    /// Asks the OS for the idle time now. Called by `tick` once a sample is due, on every hook event and on an unlock or a wake: each is a moment that already exists.
    private func sampleIdle() {
        lastIdleSample = env.now()
        step(.idle(seconds: env.idleSeconds()))
    }

    private func take() -> Int { defer { nextId += 1 }; return nextId }

    /// The nudge a note stands for, to ask the rules for its words again.
    private func nudge(of note: SKNote) -> SKNudge? {
        guard let key = note.key, let agent = note.agentId else { return nil }
        return SKNudge(kind: note.kind, reasonId: String(note.kind.dropFirst(6)), key: key, agentId: agent)
    }

    /// A nudge about a session that has moved on is moot: the request was answered, or the agent spoke again. A loop or an errors nudge that is HELD (never shown) is moot once its rule no longer fires
    /// (a successful edit ended the loop, a success broke the run of failures): the rule is asked again, not the time of the last event, because a loop that goes on keeps sending events. The one on
    /// screen is left to run out its time.
    private func stale(_ note: SKNote, shown: Bool) -> Bool {
        guard let key = note.key, let s = ledger.sessions.first(where: { $0.key == key }) else { return note.kind != "recap" }
        if s.endedAt != nil { return true }
        switch note.kind {
        case "stuck.waiting": return s.state != "approval" || s.pendingApprovalAt == nil || env.stepBackEnd(s.sessionId) != nil
        case "stuck.silent": return s.lastEventAt >= note.createdAt
        case "stuck.loop": return !shown && !SidekickStuck.loopFires(s, now: env.now())
        case "stuck.errors": return !shown && !SidekickStuck.errorsFire(s, now: env.now())
        default: return false
        }
    }

    /// What the stuck rules are told: the rate limit, the user away, the card on screen, and the kinds the user muted (so a muted loop cannot hide a quiet session, and the clock is not set for a muted deadline).
    private func stuckContext() -> SKStuckContext {
        SKStuckContext(ratelimit: env.ratelimited(), away: presence.isAway, cardShown: env.ownCardShown(), platform: env.platform, muted: store.settings.mutedKinds)
    }

    /// The ledger the stuck rules read. Their one card flag is for the whole ledger, so a session whose request stepped back to its own app (focus awareness) is held per session here: its
    /// wait is taken out of the copy the rule sees (no pending approval, so no waiting deadline and no waiting nudge), and the other sessions are read as they are. The ledger itself is not changed.
    private func ruleLedger() -> SKLedger {
        SKLedger(sessions: ledger.sessions.map { s in
            guard s.state == "approval", env.stepBackEnd(s.sessionId) != nil else { return s }
            var held = s; held.pendingApprovalAt = nil; return held
        })
    }

    private func input(for n: SKNote, now: Double) -> SKShowInput {
        SKShowInput(on: store.settings.on, kind: n.kind, dismissals: store.settings.dismissals, away: presence.isAway, ratelimit: env.ratelimited(), card: env.cardInFront(), ownCard: env.ownCardShown(),
                    inputFocused: env.typing(), visible: notes.visible, lastShownAt: notes.lastShownAt, now: now, nudged: false, recapGiven: notes.recapGiven(for: n.awaySince))
    }

    private func retireShowing() {
        guard let note = notes.retire() else { return }
        showing = nil
        env.retract(note)
    }

    /// Another view (a finished task, an error) has taken the island from the note on screen. The note goes, and it is not a dismissal. If nobody had seen it, it was never given: a recap goes back
    /// to the held notes (with its own hold) and a nudge's mark is undone, so the rules offer it again. A note the user has seen is given.
    private func retireCovered(_ s: SidekickNotes.Showing, by view: String) {
        retireShowing()
        guard !s.seen else { return }
        coveredBy = view
        notes.lastShownAt = lastShownBefore
        if s.note.isRecap { notes.recapGivenFor = nil; notes.offer(s.note, now: env.now()) }
        else if let key = s.note.key { ledger = SKLedger(sessions: ledger.sessions.map { var c = $0; if c.key == key { c.nudgedAt = nil }; return c }) }
    }

    /// The heart of it. Re-entrant calls (the app reacting to a note it was just told to present) run once more afterwards, never inside.
    func evaluate() {
        if evaluating { again = true; return }
        evaluating = true
        defer { evaluating = false }
        // A stepped-back mark has run out since the last look: the app redraws its pill (the dot and the note are read when drawn). Its time is passed, so nothing else is.
        if let lapse = focusLapseAt, env.now() >= lapse { focusLapseAt = nil; env.focusLapsed() }
        repeat {
            again = false
            run()
        } while again
        // Only a lapse still to come is kept: a mark that has run out was told once above.
        let now = env.now()
        focusLapseAt = env.focusLapseAt().flatMap { $0 > now ? $0 : nil }
        clock.set(deadline())
    }

    private func run() {
        let now = env.now()
        // A clock that reads a time which is not finite changes nothing: the pruning below would take it for "long ago" and wipe every session.
        guard now.isFinite else { return }
        ledger = SidekickLedger.prune(ledger, now: now)
        // The master switch off: nothing shows, and a note on screen goes.
        if !store.settings.on, showing != nil { retireShowing() }
        // A note on screen that another view has taken the island from is gone from the screen. The wait for that view to go is over once the island is open on another one.
        let open = env.openView()
        if coveredBy != nil, open != coveredBy { coveredBy = nil }
        if let s = notes.showing, let open, open != "sidekick" { retireCovered(s, by: open) }
        // A note on screen that has had its time goes quietly (it is not a dismissal), unless the pointer is on it.
        if notes.showingExpired(now: now) { if env.pointerOver() { notes.extendShowing(to: now + 10000) } else { retireShowing() } }
        // A held note that has had its time is dropped silently.
        _ = notes.dropExpired(now: now)
        // The stuck rules: at most one nudge, once per session. The contract's `markNudged` is the app's to call, and this is where the app calls it: when the nudge is actually SHOWN (below), not
        // when it is made. A nudge that is held and dropped without ever showing was never given, so the session may be nudged again (the same held note is not kept twice).
        if store.settings.on {
            let r = SidekickStuck.step(ruleLedger(), now: now, ctx: stuckContext())
            if let n = r.nudge {
                notes.offer(SKNote(id: take(), kind: n.kind, text: SidekickStuck.text(n, ledger, now: now, platform: env.platform), key: n.key, agentId: n.agentId, createdAt: now), now: now)
            }
        }
        // A nudge that is no longer true goes, and the waiting nudge's words change in place at the app's give-up time (it is not a second nudge).
        for n in notes.queue + (showing.map { [$0] } ?? []) where !n.isRecap {
            if stale(n, shown: showing?.id == n.id) { if showing?.id == n.id { retireShowing() } else { notes.drop(n.id) }; continue }
            if n.kind == "stuck.waiting", let nu = nudge(of: n) { notes.retext(kind: n.kind, key: n.key, text: SidekickStuck.text(nu, ledger, now: now, platform: env.platform)); if showing?.id == n.id { showing = notes.showing?.note } }
        }
        // The first held note the gate lets through shows. A note that can never show (the switch is off, its kind is muted, its period has had its recap) is dropped now.
        for n in notes.queue {
            let d = SidekickGate.shouldShow(input(for: n, now: now))
            if ["off", "kind", "muted", "recapGiven"].contains(d.reason) { notes.drop(n.id); continue }
            guard d.show, env.canHost(), coveredBy == nil || coveredBy != open else { continue }
            if d.replace { retireShowing() }
            let before = notes.lastShownAt
            guard let shown = notes.show(n.id, now: now) else { continue }
            lastShownBefore = before
            showing = shown
            if !shown.isRecap, let key = shown.key { ledger = SidekickStuck.markNudged(ledger, key: key, now: now) }   // given: it has been shown
            env.present(shown)
            if shown.isRecap, store.settings.local { polish(shown) }
            break
        }
    }

    /// A nicer sentence for a recap, if a local model has one in time: it replaces the words once, and only if the pointer is not on the note.
    private func polish(_ note: SKNote) {
        polishTask = Task { @MainActor [weak self] in
            guard let self, let nicer = await self.env.polish(note) else { return }
            guard self.showing?.id == note.id, !self.env.pointerOver() else { return }
            self.notes.retext(kind: note.kind, key: note.key, text: nicer)
            self.showing = self.notes.showing?.note
        }
    }

    /// The nearest time something must be looked at again: a stuck rule falls due, a held note runs out, or the note on screen has had its time. nil when nothing runs (the clock is then not set).
    private func deadline() -> Double? {
        let now = env.now()
        let stuck = store.settings.on ? SidekickStuck.step(ruleLedger(), now: now, ctx: stuckContext()).nextAt : nil
        // A waiting nudge that is held or on screen changes its words when the app gives up on the request.
        let giveUp = (notes.queue + (showing.map { [$0] } ?? [])).compactMap { n -> Double? in
            guard n.kind == "stuck.waiting", let key = n.key, let at = ledger.sessions.first(where: { $0.key == key })?.pendingApprovalAt else { return nil }
            let due = at + (SidekickStuck.giveUpMs[env.platform] ?? SidekickStuck.giveUpMs["mac"]!)
            return due > now ? due : nil
        }.min()
        // A stepped-back mark runs out on its own (ten minutes): a held waiting nudge is due again then, and the app redraws (`focusLapseAt`). A blocked agent sends no more events, so nothing else would wake the engine.
        return [stuck, notes.nextDeadline, giveUp, focusLapseAt].compactMap { $0 }.min()
    }
}
