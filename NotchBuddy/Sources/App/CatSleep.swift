import Foundation

// The sleep timer: an idle cat falls asleep after ten minutes with no agent event, and any agent event, hover or click wakes it (Playful wakes with
// zoomies: that is the engine's own rule). One one-shot timer, set when the cat is idle and reset by every event, so nothing polls and a hidden
// island costs nothing. The rules themselves are `CatRules` (`sleepDelay`, `wakes`, `shown`; tests/fixtures/cat/sequence-cases.json pins them);
// this class only keeps the time. It takes its clock and its timer from outside, so a test moves both by hand. Foundation only.

@MainActor
final class CatSleepClock {
    /// Cancels a scheduled call.
    typealias Cancel = () -> Void

    /// Music counts toward keeping an idle cat awake only when the cat can dance to it: both music playing AND the music integration is active.
    /// Otherwise a card waiting for user input keeps it awake, or an approval waiting inside a chat.
    static func keepsAwake(musicPlaying: Bool, musicIntegrationOn: Bool, cardWaiting: Bool, chatApprovalWaiting: Bool) -> Bool {
        (musicPlaying && musicIntegrationOn) || cardWaiting || chatApprovalWaiting
    }

    private let now: () -> Double
    private let schedule: (_ afterMs: Double, _ fire: @escaping @MainActor @Sendable () -> Void) -> Cancel
    /// True while something else keeps an idle cat awake: music playing with the integration active (the cat can dance) or a card waiting for the user. Asked when the timer fires; if it says yes the ten minutes start again.
    private let keepAwake: () -> Bool
    private var cancel: Cancel?
    private var state: CatState = .idle
    private var lastEvent: Double
    private(set) var asleep = false
    /// Called when the cat falls asleep (true) or wakes (false).
    var onChange: ((Bool) -> Void)?

    /// `now` is milliseconds, `schedule` runs `fire` once after `afterMs` and returns a way to cancel it.
    init(now: @escaping () -> Double, schedule: @escaping (Double, @escaping @MainActor @Sendable () -> Void) -> Cancel, keepAwake: @escaping () -> Bool = { false }) {
        self.now = now; self.schedule = schedule; self.keepAwake = keepAwake
        lastEvent = now()
    }

    /// Starts the clock: the cat is idle, so the ten minutes begin now.
    func start() { lastEvent = now(); rearm() }

    /// The state the cat would show if it were awake changed. Only an idle cat sleeps: any other state (an approval or a question included) stops the
    /// timer and wakes the cat, and idle starts the ten minutes.
    func stateChanged(_ new: CatState) {
        guard new != state else { return }
        state = new
        lastEvent = now()
        setAsleep(false)
        rearm()
    }

    /// An agent event (any hook event): the cat wakes and the ten minutes start again.
    func agentEvent() {
        lastEvent = now()
        setAsleep(false)
        rearm()
    }

    /// A hover or a click (`CatRules.wakes`) wakes a sleeping cat and restarts the ten minutes. On an awake cat it does nothing: moving the pointer over
    /// the island does not push bedtime back.
    func wake(_ kind: String) {
        guard asleep, CatRules.wakes(kind) else { return }
        lastEvent = now()
        setAsleep(false)
        rearm()
    }

    private func rearm() {
        cancel?(); cancel = nil
        guard !asleep, let delay = CatRules.sleepDelay(state: state, quietMs: now() - lastEvent) else { return }
        cancel = schedule(delay) { [weak self] in self?.fire() }
    }

    private func fire() {
        cancel = nil
        guard let delay = CatRules.sleepDelay(state: state, quietMs: now() - lastEvent) else { return }   // the state changed on the way: nothing to do
        if delay > 1 { cancel = schedule(delay) { [weak self] in self?.fire() }; return }                 // the timer was early: wait for the rest
        if keepAwake() { lastEvent = now(); rearm(); return }
        setAsleep(true)
    }

    private func setAsleep(_ value: Bool) {
        guard value != asleep else { return }
        asleep = value
        onChange?(value)
    }
}
