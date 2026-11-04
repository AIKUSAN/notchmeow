import CoreGraphics
import Foundation

// The compact island steps aside for the pointer: the rules, as plain numbers and times. The compact island is a strip with the notch in the middle and a wing on each side (the left holds the big cat,
// the right the grid of agent cats and the shelf's badge). On a crowded menu bar the wings sit on other apps' icons, and macOS has no way to move them. While the pointer is over EITHER wing the whole
// island swooshes into the notch (its frame shrinks to the notch's width on a spring), its cats, grid and badges fade as it shrinks, and the panel passes the mouse on to the icons under both wings;
// `returnDelay` seconds after the pointer has left both wings it swooshes back out. The right wing (the grid) folds the island at once; the left wing (the big cat) only after the pointer has rested
// there `leftDwell` seconds with no mouse button pressed, and any press during the dwell cancels it, so a quick click, the drag of the cat's head out to the desktop and a right-click (the Wardrobe menu)
// on the big cat work as they always did. The notch itself is not a wing: the pointer there is the island's own hover (Open on hover, with its dwell, lives
// there). The hover zones stay where the full island is, so leaving is measured against the original wings, not the shrunk island. An alert cancels the step-aside at once. Foundation only:
// `IslandWindowController.pollFrame` feeds it the pointer and the clock it already has, so it adds no timer, no monitor and no poll (`docs/SPEC.md`, "L'aile droite s'efface").

enum IslandWing {
    /// How long the cats, the grid and the badges take to fade out as the island shrinks (s), and to fade back in (s). The panel stops taking the mouse at once; only the picture moves.
    static let fadeOut: TimeInterval = 0.15
    static let fadeIn: TimeInterval = 0.25
    /// How long the pointer must have been away from both wings before the island swooshes back out (s).
    static let returnDelay: TimeInterval = 1.0
    /// How long the pointer must rest on the LEFT wing, with no mouse button pressed, before the island folds (s). The right wing folds it at once.
    static let leftDwell: TimeInterval = 0.4
    /// The slack the dwell's comparison allows, so that 0.4 s on a clock of binary fractions is 0.4 s.
    private static let epsilon: TimeInterval = 1e-9
    /// The swoosh is a spring: about 0.22 s to settle, with a slight overshoot (a damping fraction a little under 1).
    static let springResponse: TimeInterval = 0.22
    static let springDamping: Double = 0.68

    /// The two wings in the panel's coordinates, each the strip's whole height: the left from the island's left edge to the notch's left edge, the right from the notch's right edge to the island's
    /// right edge. `island` is the compact island's FULL frame and `notchWidth` the notch's. `slop` is how far the island's hover area reaches beyond the strip (6 pt on a notch screen, 0 on a screen
    /// without one): each wing takes it on its outer side, top and bottom, and not on the side towards the notch.
    struct Wings: Equatable {
        var left: CGRect
        var right: CGRect
        func contains(_ p: CGPoint) -> Bool { left.contains(p) || right.contains(p) }
        /// Which wing the point is in, if any.
        func zone(of p: CGPoint) -> Zone? { left.contains(p) ? .left : right.contains(p) ? .right : nil }
    }

    enum Zone: Equatable { case left, right }

    static func wings(island: CGRect, notchWidth: CGFloat, slop: CGFloat = 0) -> Wings {
        let notchLeft = island.midX - notchWidth / 2, notchRight = island.midX + notchWidth / 2
        let leftWidth = max(0, notchLeft - (island.minX - slop)), rightWidth = max(0, island.maxX + slop - notchRight)
        return Wings(left: CGRect(x: island.minX - slop, y: island.minY - slop, width: leftWidth, height: island.height + 2 * slop),
                     right: CGRect(x: notchRight, y: island.minY - slop, width: rightWidth, height: island.height + 2 * slop))
    }

    /// The width the island shrinks to: the notch's own.
    static func foldedWidth(notchWidth: CGFloat) -> CGFloat { notchWidth }

    /// The island's drawn width at `swoosh` (0 at rest, 1 folded into the notch): linear, for the contact sheet; the app lets a spring move it.
    static func width(full: CGFloat, notchWidth: CGFloat, swoosh: Double) -> CGFloat { full - (full - foldedWidth(notchWidth: notchWidth)) * CGFloat(swoosh) }

    /// Whether the island can step aside now: only in the compact island, not while the greeting's tail still draws the session cats in the grid's place, not while a drag of the cat's head is under
    /// way, and not while an alert wants the island (a permission request or question waits, a file is on its way in, the desktop cat is flying to or from the notch, the shelf holds the island).
    static func isActive(compact: Bool, greetingTail: Bool, dragging: Bool, alert: Bool) -> Bool { compact && !greetingTail && !dragging && !alert }

    /// The island's memory between two ticks.
    struct Yield: Equatable {
        struct Out: Equatable {
            /// The island is folded into the notch (or folding).
            var faded: Bool
            /// The pointer is over a wing of the folded island: the panel must not take the mouse, and the island must not count the pointer as over it.
            var passThrough: Bool
        }

        private var faded = false
        /// When the pointer was first seen away from both wings (while folded); nil while it is over one.
        private var leftAt: TimeInterval?
        /// When the pointer began to rest on the left wing with no button pressed (before the island has folded); nil otherwise.
        private var restSince: TimeInterval?

        /// One tick. `zone`: the wing the pointer is in, if any. `active`: `isActive`. `buttonDown` says whether any mouse button is held (a file being dragged in, a click that began on the big cat, a
        /// right-click): then no fold begins, a dwell on the left wing starts over, and a fold that has begun is not undone by it. It is asked only while the pointer is in a wing and the island has not
        /// folded yet, so a poll tick that is not near a wing costs nothing.
        mutating func step(now: TimeInterval, zone: Zone?, active: Bool, buttonDown: () -> Bool) -> Out {
            guard active, now.isFinite else {
                self = Yield()
                return Out(faded: false, passThrough: false)
            }
            if let zone {
                leftAt = nil
                if faded { return Out(faded: true, passThrough: true) }
                switch zone {
                case .right:
                    restSince = nil
                    if !buttonDown() { faded = true }
                case .left:
                    if buttonDown() {
                        restSince = nil
                    } else {
                        let since = restSince ?? now
                        restSince = since
                        if now - since + IslandWing.epsilon >= IslandWing.leftDwell { faded = true }
                    }
                }
                return Out(faded: faded, passThrough: faded)
            }
            restSince = nil
            if faded {
                let since = leftAt ?? now
                leftAt = since
                if now - since >= IslandWing.returnDelay { self = Yield() }
            }
            return Out(faded: faded, passThrough: false)
        }
    }
}
