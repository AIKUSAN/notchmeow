import CoreGraphics
import Foundation

// The shelf's badge on the compact island (sub-project G1): a small count at the right end of the right wing, one more cell beside the grid of agent cats. Pure rules, Foundation and
// CoreGraphics only. It shows only while the island is already compact and the shelf is not empty: it never keeps an island visible and never wakes a hidden one. It fades with the wing
// (`IslandWing`, unchanged) because it is drawn with the grid; it does not touch Two cats or the kitten layouts, which do not use the wing's right end.

enum ShelfBadge {
    /// The badge's diameter (pt) in the 32 pt strip, and how far its centre is from the island's right edge. The grid's cells are 12 pt wide, centred 40 pt in, so its right edge is 26 pt in;
    /// the badge's left edge is 21 pt in, 5 pt clear of the last cell.
    static let diameter: CGFloat = 14
    static let inset: CGFloat = 14
    /// How far beyond the badge a click still counts as on it.
    static let hitSlop: CGFloat = 4

    /// Whether the badge is on screen: only in the compact island, with something on the shelf, and not while the greeting's tail still draws the session cats in the grid's place.
    static func isShown(compact: Bool, count: Int, greetingTail: Bool) -> Bool { compact && !greetingTail && count > 0 }

    /// The strip shrinks the grid below 32 pt (`IslandRestingLayout.miniGridScale`); the badge shrinks with it.
    static func scale(height: CGFloat) -> CGFloat { min(1, max(0, height - 4) / 28) }

    /// The badge's centre in the island's own coordinates (y down, the island's top left the origin).
    static func center(islandWidth: CGFloat, height: CGFloat) -> CGPoint { CGPoint(x: islandWidth - inset, y: height / 2) }

    /// The rectangle a click counts in, in the same coordinates as `island` (the island's frame in the panel, whichever way y runs).
    static func hitRect(island: CGRect) -> CGRect {
        let k = scale(height: island.height)
        let r = diameter / 2 * k + hitSlop
        return CGRect(x: island.maxX - inset - r, y: island.midY - r, width: 2 * r, height: 2 * r)
    }
}
