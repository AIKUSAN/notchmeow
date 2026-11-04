import CoreGraphics
import Foundation

// A click outside the open island folds it at once (Mac). The rules, as plain values: when a click counts, and when the island stays. Foundation only. `IslandWindowController` owns the one
// global mouse monitor, which exists only while the island is expanded (installed when the mode becomes expanded, removed when it leaves it: no monitor when the island is compact or
// hidden), and asks this file what the click means. The monitor sees only events of other apps, so a click on the island itself, on NotchMeow's Settings or on its Wardrobe menu never reaches it.

enum IslandOutsideClick {
    /// A press that moves farther than this (pt) before it is released is a drag (a file taken out of a Finder window, a window moved, a selection), not a click.
    static let clickSlop: CGFloat = 4

    /// What the app knows when the click is released.
    struct Context: Equatable {
        /// The island is expanded.
        var expanded: Bool
        /// The user pinned it open (⌘P).
        var pinned: Bool
        /// A permission request or a question waits for an answer (the island's own card or a chat's), and the shelf's drag-out or share picker holds the island open: `fsm.isHeldOpen`'s
        /// and `EscapeRouting`'s rules.
        var held: Bool
        /// The user is typing in the chat: the chat view is showing and a text field has the keyboard.
        var typing: Bool
        /// The pointer is over the island (its hover area): a click there is not outside.
        var pointerInIsland: Bool
        /// The cat's head is being dragged out, or the Wardrobe menu is open.
        var busy: Bool
    }

    /// Whether a click outside folds the island now.
    static func shouldFold(_ c: Context) -> Bool {
        c.expanded && !c.pinned && !c.held && !c.typing && !c.pointerInIsland && !c.busy
    }

    /// Tells a click from a drag: remembers where the button went down, and says on release whether the pair was a click (it did not move more than `clickSlop`).
    struct Tracker {
        private var downAt: CGPoint?

        mutating func down(at p: CGPoint) { downAt = p }

        /// The release. True when it ends a click; the press is forgotten either way. A release with no press seen (the press happened before the monitor was installed) is not a click.
        mutating func up(at p: CGPoint) -> Bool {
            defer { downAt = nil }
            guard let d = downAt else { return false }
            return hypot(p.x - d.x, p.y - d.y) <= IslandOutsideClick.clickSlop
        }

        /// Forget a press (the monitor was removed).
        mutating func reset() { downAt = nil }
    }
}
