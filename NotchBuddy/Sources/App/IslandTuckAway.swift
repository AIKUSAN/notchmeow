import Foundation

// Tuck the island away (Settings → General → Behavior): when the compact island (the notch with its ears) hides by itself. Pure Foundation: the state machine (IslandStateMachine) keeps the one timer,
// and `IslandWindowController` feeds it the live state and the activity. Tested by scripts/test-island-tuck-away.sh; the Windows and Linux twin is windows/src/island/tuckaway.ts.

enum IslandTuckAway {
    /// The UserDefaults key. Its value is one of the five raw values below; anything else reads as "never".
    static let defaultsKey = "island.tuckAway"

    /// Never (the default): the compact island never hides by itself. A time, in minutes: it hides once nothing is live and that time has passed since the last activity.
    enum Choice: String, CaseIterable {
        case never
        case m1 = "1"
        case m5 = "5"
        case m15 = "15"
        case m30 = "30"

        /// The quiet time before the island may hide, in minutes; nil for never.
        var minutes: Double? {
            switch self {
            case .never: nil
            case .m1: 1
            case .m5: 5
            case .m15: 15
            case .m30: 30
            }
        }
    }

    /// The stored value, cleaned: a missing or unknown value is never.
    static func choice(stored: String?) -> Choice {
        stored.flatMap(Choice.init(rawValue:)) ?? .never
    }

    /// The pill states that are live: a pill that is working, thinking or searching, or waiting for an answer (an approval or a question).
    static let liveStates: Set<String> = ["working", "thinking", "searching", "approval", "question"]

    /// Live now: a pill in a live state. An open session that is idle does not count, nor does a finished, idle or other pill.
    static func isLive(pillStates: [String]) -> Bool {
        pillStates.contains { liveStates.contains($0) }
    }

    /// Seconds from `now` until the compact island may hide, counted from the last activity; nil while it may not (never, or something is live). 0 is due now.
    static func hideDelay(_ choice: Choice, lastActivity: TimeInterval, now: TimeInterval, live: Bool) -> TimeInterval? {
        guard let minutes = choice.minutes, !live else { return nil }
        return max(0, lastActivity + minutes * 60 - now)
    }
}
