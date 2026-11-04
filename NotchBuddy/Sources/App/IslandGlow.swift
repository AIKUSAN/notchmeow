import Foundation

// The hover glow: a soft rainbow halo along the island's outline (blue, purple, pink, orange: `Theme.Glow`, from shared/theme.json) while the pointer is over the island, in the compact
// notch and in the open island. The rules, as plain values. Foundation only. It is drawn only while the pointer is over the island: the view (`IslandGlowView.swift`) is not even in the tree
// the rest of the time, so a hidden or idle island has no animation, no timer and no layer for it. Reduce Motion: a still glow. The Windows and Linux twin is the `glow` class of `#island`
// in windows/src/style.css, with the same colours from the same file.

enum IslandGlow {
    /// The UserDefaults key of Settings → General → Behavior → Hover glow (on by default).
    static let defaultsKey = "island.hoverGlow"
    /// Width of the bright edge along the outline (pt), and how far the same ring is blurred for the halo around it (pt); the edge is blurred a little too, so it is soft.
    static let lineWidth: Double = 3
    static let edgeBlur: Double = 1.2
    static let haloBlur: Double = 8
    /// How the halo's opacity compares with the edge's.
    static let haloOpacity: Double = 0.8
    /// Fade in on hover and out on leave (s).
    static let fade: TimeInterval = 0.2
    /// One turn of the colours around the island (s), and how often the picture is redrawn while it turns (frames per second).
    static let secondsPerTurn: TimeInterval = 8
    static let framesPerSecond: Double = 30

    /// Whether the glow is drawn: the setting is on, the pointer is over the island, and there is an island on screen (compact or open, not hidden), and the cat's head is not being dragged.
    static func isShown(enabled: Bool, pointerOver: Bool, islandOnScreen: Bool, dragging: Bool) -> Bool {
        enabled && pointerOver && islandOnScreen && !dragging
    }

    /// The angle (degrees, 0 up to 360) the colours have turned to at `time` seconds. Reduce Motion: always 0, a still glow. A time that is not a number gives 0.
    static func angle(at time: TimeInterval, reduceMotion: Bool) -> Double {
        guard !reduceMotion, time.isFinite else { return 0 }
        let turn = time.truncatingRemainder(dividingBy: secondsPerTurn) / secondsPerTurn
        return (turn < 0 ? turn + 1 : turn) * 360
    }
}
