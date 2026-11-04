import Foundation

// The desktop cat's frame-rate governor (sub-project H): the target `DesktopCatTrip.fps` gives becomes one repeating timer at that rate, re-armed only when the target changes,
// and no timer at all when the cat cannot be seen. Nothing polls: what raises the rate (the cursor coming near, a click, an agent event, a kitten) calls the controller, which
// asks again. Also `DesktopCatVisibility`, what "cannot be seen" means. Foundation only.

struct DesktopCatPacer: Equatable, Sendable {
    /// The target now; 0 means no timer.
    private(set) var fps = 0.0

    enum Action: Equatable, Sendable {
        case none
        /// Cancel the timer: the cat is not drawn or cannot be seen.
        case stop
        /// Replace the timer with one that fires every `interval` seconds, with `leeway` seconds of slack so the system can coalesce wake-ups.
        case arm(interval: Double, leeway: Double)
    }

    /// The time between frames for a target, nil for a target that means no frames (0, negative, NaN, infinity).
    static func interval(_ fps: Double) -> Double? { fps.isFinite && fps > 0 ? 1 / fps : nil }


    static func leeway(_ interval: Double) -> Double { min(interval * 0.1, 0.2) }

    /// The new target. Nothing is asked of the timer when it did not change.
    mutating func target(_ new: Double) -> Action {
        let clean = Self.interval(new) == nil ? 0 : new
        guard clean != fps else { return .none }
        fps = clean
        guard let i = Self.interval(clean) else { return .stop }
        return .arm(interval: i, leeway: Self.leeway(i))
    }

    /// The share of one core a rate costs when a frame takes `msPerFrame` milliseconds of CPU: the bench's number.
    static func coreShare(msPerFrame: Double, fps: Double) -> Double { msPerFrame * fps / 1000 }
}

/// Why the cat cannot be seen. Any one of them hides it (frame rate 0 and no timer).
struct DesktopCatVisibility: Equatable, Sendable {
    /// The displays are asleep (`NSWorkspace.screensDidSleepNotification`).
    var screensAsleep = false
    /// The session is locked or switched away (`com.apple.screenIsLocked`, `NSWorkspace.sessionDidResignActiveNotification`).
    var locked = false
    /// The window is not on screen: a fullscreen app's Space is active, or something covers it (`NSWindow.occlusionState` has no `.visible`).
    var covered = false

    var hidden: Bool { screensAsleep || locked || covered }
}
