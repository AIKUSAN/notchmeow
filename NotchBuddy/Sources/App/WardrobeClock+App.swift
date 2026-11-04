import Combine
import Foundation

// The app's way into the wardrobe clock: the real date, ONE wall-clock one-shot timer on the main queue (a Mac that sleeps through midnight fires it on waking), and the links to the
// store (the choice) and to `CatConfig` (the outfit every big cat reads on every frame). Nothing here is in the contract, and the test programs do not compile this file.

extension WardrobeClock {
    /// The app's clock. `schedule` uses the wall clock (`wallDeadline`), not the monotonic one, so a timer set for midnight is not still waiting after the Mac slept through it.
    static let shared = WardrobeClock(
        today: { appToday() },
        secondsToMidnight: { appSecondsToMidnight() },
        schedule: { afterSeconds, fire in
            let item = DispatchWorkItem { MainActor.assumeIsolated { fire() } }
            DispatchQueue.main.asyncAfter(wallDeadline: .now() + afterSeconds, execute: item)
            return { item.cancel() }
        })

    #if DEBUG && !APPSTORE
    /// Debug builds only (the cat panel's Wardrobe section): a date Auto reads instead of today's, so the owner can see each season without waiting for it, and a pretend midnight a few seconds
    /// away, so the one-shot timer can be watched. Compiled out of Release and App Store (`scripts/check-app-binary.sh` proves it).
    static var debugDay: Wardrobe.Day?
    static var debugMidnightAt: Date?
    static func appToday() -> Wardrobe.Day {
        if let at = debugMidnightAt, Date() >= at { debugMidnightAt = nil; debugDay = Wardrobe.nextDay(debugDay ?? Wardrobe.today()) }
        return debugDay ?? Wardrobe.today()
    }
    /// With a pretend midnight pending, the timer is asked for the seconds left to it (the clock adds its second of slack).
    static func appSecondsToMidnight() -> Double { debugMidnightAt.map { max(1, $0.timeIntervalSinceNow - 1) } ?? Wardrobe.secondsToMidnight() }
    #else
    static func appToday() -> Wardrobe.Day { Wardrobe.today() }
    static func appSecondsToMidnight() -> Double { Wardrobe.secondsToMidnight() }
    #endif

    private static var subscriptions = Set<AnyCancellable>()

    /// Starts the clock and keeps it in step with the app: the stored choice feeds `setChoice`, and the resolved outfit goes to `config.outfit`, which the big cats read. A change of
    /// the system clock or time zone looks at the date again (an event, not a poll).
    func attach(to store: CatSettingsStore, config: CatConfig) {
        onChange = { [weak config] outfit in config?.outfit = outfit }
        store.$wardrobe.map(\.outfit).removeDuplicates()
            .sink { [weak self, weak config] choice in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.setChoice(choice)
                    config?.outfit = self.resolved
                }
            }
            .store(in: &Self.subscriptions)
        #if DEBUG && !APPSTORE
        // The Debug cat panel's Wardrobe section talks to the clock through notifications, so the panel compiles without the app's files.
        NotificationCenter.default.publisher(for: WardrobeDev.dateNote)
            .sink { [weak self] note in MainActor.assumeIsolated { Self.debugDay = (note.userInfo?["day"] as? String).flatMap(Wardrobe.parseDay); self?.dateChanged() } }
            .store(in: &Self.subscriptions)
        NotificationCenter.default.publisher(for: WardrobeDev.midnightNote)
            .sink { [weak self] _ in MainActor.assumeIsolated { Self.debugMidnightAt = Date().addingTimeInterval(5); self?.dateChanged() } }
            .store(in: &Self.subscriptions)
        #endif
        for name in [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            NotificationCenter.default.publisher(for: name)
                .sink { [weak self] _ in MainActor.assumeIsolated { self?.dateChanged() } }
                .store(in: &Self.subscriptions)
        }
    }
}
