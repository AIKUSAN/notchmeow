import Foundation

@main
enum IslandPollerTests {
    @MainActor static func main() {
        let counter = Counter()
        let poller = IslandPoller { counter.ticks += 1 }

        // On screen: hover, click-through, the cat's look-at and the drag ghost run at 60 Hz.
        let visible = firesPerSecond(poller, hidden: false, counter)
        precondition(visible >= 45, "visible poll too slow: \(visible) Hz")

        // Hidden: only hover-to-show needs the poll, so it must not run at 60 Hz
        // (CLAUDE.md: 0 % CPU when the island is hidden) but must still run.
        let hidden = firesPerSecond(poller, hidden: true, counter)
        precondition(hidden <= 12, "hidden poll too fast: \(hidden) Hz")
        precondition(hidden >= 5, "hidden poll too slow for hover-to-show: \(hidden) Hz")

        // Revealing the island brings the 60 Hz poll back.
        let shown = firesPerSecond(poller, hidden: false, counter)
        precondition(shown >= 45, "poll did not return to 60 Hz: \(shown) Hz")

        print("IslandPoller: visible \(visible) Hz, hidden \(hidden) Hz, shown again \(shown) Hz")
    }

    @MainActor
    private static func firesPerSecond(_ poller: IslandPoller, hidden: Bool, _ counter: Counter) -> Int {
        poller.run(hidden: hidden)
        counter.ticks = 0
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        return counter.ticks
    }
}

@MainActor
private final class Counter {
    var ticks = 0
}
