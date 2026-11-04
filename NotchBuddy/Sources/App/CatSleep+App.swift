import Combine
import Foundation
import QuartzCore

// The app's way into the sleep clock: real time, a one-shot timer on the main queue, what keeps an idle cat awake, and the link to `AppState`.
// Nothing here is in the contract, and the test programs do not compile this file.

extension CatSleepClock {
    /// The app's clock. An idle cat stays awake while Apple Music plays (and the music integration is active, so it can dance), while a card waits for an answer, or while an approval waits inside a chat.
    static let shared = CatSleepClock(
        now: { CACurrentMediaTime() * 1000 },
        schedule: { afterMs, fire in
            let item = DispatchWorkItem { MainActor.assumeIsolated { fire() } }
            DispatchQueue.main.asyncAfter(deadline: .now() + afterMs / 1000, execute: item)
            return { item.cancel() }
        },
        keepAwake: {
            let app = AppState.shared
            #if !APPSTORE
            let musicPlaying = app.musicPlaying
            let chatApprovalWaiting = app.chatApproval != nil
            #else
            let musicPlaying = false
            let chatApprovalWaiting = false
            #endif
            return CatSleepClock.keepsAwake(musicPlaying: musicPlaying, musicIntegrationOn: app.activeIntegrations.contains("integration_music"), cardWaiting: app.pendingApproval != nil || app.pendingQuestion != nil, chatApprovalWaiting: chatApprovalWaiting)
        })

    private static var subscriptions = Set<AnyCancellable>()

    /// Starts the clock and keeps it in step with the app: the state the cat would show if it were awake (the override, else the focused task's)
    /// feeds `stateChanged`, and when the clock puts the cat to sleep or wakes it, `AppState.catAsleep` follows.
    func attach(to app: AppState) {
        // When the cat falls asleep (ten minutes with no agent event) a kitten whose stop never came goes too: the only cleanup besides the parent's stop and its session ending.
        onChange = { [weak app] asleep in
            app?.catAsleep = asleep
            if asleep { app?.sweepKittens() }
        }
        app.$tasks.combineLatest(app.$focusId, app.$stateOverride)
            .map { tasks, focus, forced -> CatState in
                let state = forced ?? (tasks.first { $0.id == focus } ?? tasks.first)?.state ?? .idle
                return CatState(rawValue: state.rawValue) ?? .idle
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in MainActor.assumeIsolated { self?.stateChanged(state) } }
            .store(in: &Self.subscriptions)
        start()
    }
}
