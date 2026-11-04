import Combine
import Foundation

// The agent sidekick (sub-project F1) in the app: the one `SidekickEngine` with the app's own clock, one-shot timer and settings, and the few things it asks the app (what is in front of the island, whether an
// agent is rate-limited). It reads the hook events the app already receives, never sends anything and never decides anything: a request is answered only by the user's click. `HookServer` feeds it at the top
// of each handler, BEFORE the pending-approval gate, so a request that is displaced or declined is still counted. The rules are pure files (`Sidekick*.swift`) tested against tests/fixtures/sidekick/ and the
// engine is tested with a clock and a timer by hand (tests/SidekickEngineTests.swift); this file is the thin app side, and tests/SidekickWiringTests.swift pins where it is called from.
// Its memory is the ledger: a basename, a command key and counts per session, in memory only, never written to disk, never logged. It starts no timer of its own: the engine's ONE one-shot clock is set only
// while something is waiting for a deadline (`SidekickClock`).

@MainActor
final class Sidekick {
    static let shared = Sidekick()

    /// The sidekick's clock, in ms: wall time, so the minutes a Mac spent asleep count as time away.
    static func nowMs() -> Double { Date().timeIntervalSince1970 * 1000 }

    /// In the binary of every build (Debug, Release and App Store): `scripts/check-app-binary.sh` looks for it. It is longer than 15 bytes on purpose (Swift keeps a shorter string inside the code, where
    /// `strings` cannot see it), and the note's view uses it as its accessibility identifier, so a Release build cannot drop it as unused.
    static let marker = "NM_SIDEKICK_ENGINE_PRESENT"

    #if APPSTORE
    static let codexEnabled = false
    #else
    static let codexEnabled = true
    #endif

    /// The user's real home folder, for the risk rules (`~` and `$HOME` in a command): the sandbox's container home would be the wrong one in the App Store build.
    static let realHome: String = getpwuid(getuid()).flatMap { String(validatingCString: $0.pointee.pw_dir) } ?? NSHomeDirectory()

    /// What only the island's window knows (is the user typing, is the pointer on it), set once at launch by `AppDelegate`.
    final class Inputs {
        var typing: () -> Bool = { false }
        var pointerOver: () -> Bool = { false }
        /// Where the island was when a note opened it, to put it back afterwards.
        var mode: IslandMode = .compact
        var collapsePending = false
    }
    let inputs = Inputs()
    let engine: SidekickEngine
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // One one-shot timer on the main queue, on the wall clock (it keeps counting while the Mac sleeps). `SidekickClock.set` is the only caller, and sets it only while a deadline is waiting.
        // The delay is clamped to 0...24 h and a number that is not finite is 0: an early fire is harmless (`SidekickClock.fire` waits for the rest), a trap on a conversion is not.
        let clock = SidekickClock(now: { Sidekick.nowMs() }, schedule: { afterMs, fire in
            let seconds = afterMs.isFinite ? min(max(afterMs, 0), 24 * 3_600_000) / 1000 : 0
            let item = DispatchWorkItem { MainActor.assumeIsolated { fire() } }
            DispatchQueue.main.asyncAfter(wallDeadline: .now() + seconds, execute: item)
            return { item.cancel() }
        })
        var env = SidekickEngine.Env(now: { Sidekick.nowMs() })
        env.cardInFront = {
            let app = AppState.shared
            #if !APPSTORE
            if app.chatApproval != nil { return "approval" }
            #endif
            return app.pendingApproval != nil ? "approval" : app.pendingQuestion != nil ? "question" : nil
        }
        env.ownCardShown = { let app = AppState.shared; return app.pendingApproval != nil && app.mode == .expanded && app.view == .approval }
        // The mark's end, in the sidekick's clock (ms): the mark's age is read in seconds since the reference date, the clock is the wall clock, so the rest of the lifetime is added to the clock's now.
        env.stepBackEnd = { sessionId in
            guard let mark = AppState.shared.focusMarks.forSession(sessionId, now: FocusAwareApp.now()) else { return nil }
            return FocusAware.lapseMs(markAt: mark.at, now: FocusAwareApp.now(), nowMs: Sidekick.nowMs())
        }
        // The earliest end (ms, the sidekick's clock) of any live mark, whatever its session: the marks are the source, not the ledger (which evicts sessions), so a session the ledger has dropped still wakes the app at its lapse.
        env.focusLapseAt = {
            let now = FocusAwareApp.now()
            return AppState.shared.focusMarks.live(now: now).map { FocusAware.lapseMs(markAt: $0.at, now: now, nowMs: Sidekick.nowMs()) }.min()
        }
        // A mark that runs out redraws the app's pill: its dot and note are read when drawn, and nothing else wakes the app for a blocked agent (the engine's clock, whatever the switch).
        env.focusLapsed = { AppState.shared.objectWillChange.send() }
        env.openView = { let app = AppState.shared; return app.mode == .expanded ? app.view.rawValue : nil }
        env.ratelimited = { AppState.shared.tasks.contains { $0.state == .ratelimit } }
        env.idleSeconds = { PresenceMonitor.idleSeconds() }
        let inputs = self.inputs
        env.canHost = { let app = AppState.shared; return SidekickHost.canHost(expanded: app.mode == .expanded, view: app.view.rawValue) }
        env.typing = { inputs.typing() }
        // A nicer sentence for a recap, from a model on this computer if there is one (never the chat's Auto choice, which could be a cloud model). The template is shown first and stands otherwise.
        env.polish = { note in await SidekickVoiceApp.nicer(lines: note.text.components(separatedBy: "\n"), facts: note.facts) }
        env.pointerOver = { inputs.pointerOver() }
        // A note opens the island on its own row the way a finished task does (`.hookExpand`): no window of its own, and never over a card, the chat or Settings (`canHost`).
        env.present = { _ in
            inputs.mode = AppState.shared.mode
            inputs.collapsePending = false
            NotificationCenter.default.post(name: .hookExpand, object: IslandView.sidekick)
        }
        // The island goes back to where it was: the overview, and folded if the note had opened it. The fold waits one turn, so a note that replaces this one does not make the island blink.
        env.retract = { _ in
            let app = AppState.shared
            guard app.view == .sidekick else { return }
            app.view = app.tasks.isEmpty ? .empty : .overview
            guard inputs.mode != .expanded else { return }
            inputs.collapsePending = true
            DispatchQueue.main.async {
                guard inputs.collapsePending, Sidekick.shared.engine.showing == nil else { return }
                inputs.collapsePending = false
                NotificationCenter.default.post(name: .islandCollapse, object: nil)
            }
        }
        engine = SidekickEngine(store: .shared, clock: clock, env: env, codex: Self.codexEnabled)
        // A lock, a sleep or a dark display, from the monitor the desktop cat shares: no observers of its own.
        PresenceMonitor.shared.subscribe("sidekick") { [weak self] event in self?.engine.presenceEvent(event) }
        PresenceMonitor.shared.start()
        // The waiting nudge is for a request whose card is NOT on screen: when the card shows or hides, its deadline changes. A note on screen is covered when another view takes the island from it.
        // Both are read from the view the island is open on, so one signal serves: it changes when the island opens, folds or switches view.
        let app = AppState.shared
        engine.watch(app.$view.combineLatest(app.$mode).map { $1 == .expanded ? $0.rawValue : "" }.removeDuplicates().dropFirst()).store(in: &cancellables)
        // A change of a setting (the switch, Unmute) decides again what may show.
        engine.watch(SidekickStore.shared.$settings.dropFirst()).store(in: &cancellables)
    }

    /// A hook payload at the feed point (`HookServer.processEvent`, `processPermissionRequest` and `processQuestionRequest`). An event the ledger does not know is nothing.
    func feed(payload: [String: Any]) { engine.feed(payload: payload) }

    /// The user answered an approval card (Deny, Allow or Always): the one event that is not a hook.
    func approvalAnswered(agentId: String, sessionId: String) { engine.approvalAnswered(agentId: agentId, sessionId: sessionId) }

    /// A tick the island already has: `IslandWindowController.pollFrame`. The engine reads the idle time only when a sample is due (see `SidekickIdle`), so most ticks do nothing.
    func tick() { engine.tick() }

    /// The agents that have a live session (one that has not ended): the pills a drop may hand a path to.
    var liveAgents: Set<String> { engine.liveAgents }
}
