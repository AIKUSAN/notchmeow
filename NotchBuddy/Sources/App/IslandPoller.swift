import Foundation

/// The island's mouse-poll timer: 60 Hz while the island is on screen, 10 Hz while it
/// is hidden, where the poll only has to notice the mouse entering the notch
/// (CLAUDE.md: 0 % CPU when the island is hidden).
@MainActor
final class IslandPoller {
    static let visibleInterval: TimeInterval = 1.0/60.0
    static let hiddenInterval: TimeInterval = 1.0/10.0

    private let tick: @MainActor () -> Void
    private var timer: Timer?
    private var hidden: Bool?

    init(tick: @escaping @MainActor () -> Void) {
        self.tick = tick
    }

    /// Starts the poll, or restarts it at the rate for `hidden`. Same rate: no-op.
    func run(hidden: Bool) {
        guard hidden != self.hidden else { return }
        self.hidden = hidden
        timer?.invalidate()
        let interval = hidden ? Self.hiddenInterval : Self.visibleInterval
        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.tick() }
        }
        // Hidden: let macOS coalesce the wake-ups with other timers.
        if hidden { t.tolerance = interval / 10 }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}
