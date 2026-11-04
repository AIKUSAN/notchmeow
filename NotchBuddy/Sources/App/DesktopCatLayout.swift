import Foundation

// The desktop cat's geometry (sub-project H): AppKit's screens turned into the contract's, the window around the cat, which side its kittens go on, and the shape of its body.
// Everything is in points. A "spot" is the head centre in the contract's coordinates (y down, the origin at the top left of the main screen); a point "relative to the head"
// has x right and y down from that centre. The window is sized for the cat, its badge and its kittens, and no larger: the clicks outside `hits` pass through it
// (`DesktopCatPanel`). Foundation only; `tests/DesktopCatLayoutTests.swift` pins every number.

enum DesktopCatScreens {
    /// A screen as AppKit reports it: `NSScreen.frame` and `visibleFrame`, bottom-left origin. `NSScreen.screens[0]` is the one with the menu bar.
    struct AppKitScreen: Equatable, Sendable {
        var frame: DesktopRect
        var visible: DesktopRect
    }

    /// The height of the main screen: AppKit's y of its top edge. Every conversion flips around it.
    static func primaryHeight(_ screens: [AppKitScreen]) -> Double { screens.first.map { $0.frame.y + $0.frame.h } ?? 0 }

    /// AppKit's screens as the contract's: `yTop = primaryHeight - frame.maxY`, the first one marked main. The result is not tidied here: `DesktopCatSpots` tidies it.
    static func contract(_ screens: [AppKitScreen]) -> [DesktopScreen] {
        let top = primaryHeight(screens)
        func flip(_ r: DesktopRect) -> DesktopRect { DesktopRect(x: r.x, y: top - (r.y + r.h), w: r.w, h: r.h) }
        return screens.enumerated().map { DesktopScreen(frame: flip($1.frame), visible: flip($1.visible), main: $0 == 0) }
    }

    /// An AppKit point (`NSEvent.mouseLocation`) as a spot, and back.
    static func spot(fromAppKit x: Double, _ y: Double, primaryHeight: Double) -> DesktopSpot { DesktopSpot(x: x, y: primaryHeight - y) }
    static func appKit(_ s: DesktopSpot, primaryHeight: Double) -> (x: Double, y: Double) { (s.x, primaryHeight - s.y) }
}

/// The window around the cat, in points: its size, and where the head centre is inside it (y down from the window's top).
struct DesktopCatFrame: Equatable, Sendable {
    var w: Double, h: Double
    var headX: Double, headY: Double
}

enum DesktopCatLayout {
    /// The cat is drawn in a square of D / 0.6 (the head, the ears, the whiskers and the badge are inside it), as everywhere in the app.
    static let canvasK = 1 / 0.6
    /// Room above the canvas for the hearts of a happy cat: 40 pt at the island's Ø58 head, in proportion at the other sizes.
    static let heartsK = 40.0 / 58.0
    /// The body takes the mouse inside the head circle (a little larger than the head, for the ears), the badge's circle and the kittens' circles.
    static let headK = 0.55, badgeX = 0.7, badgeY = -0.46, badgeK = 0.2

    /// The width of a "+N" or "×N" label of size `size` (`CatKittenDraw.labelWidth`).
    static func labelWidth(_ text: String, _ size: Double) -> Double { let sz = max(8, size); return Double(text.count) * sz * 0.62 + sz * 0.9 }

    /// A kitten's state dot as `CatEffects.drawBadge` draws it at rest, in units of its head's R (`D / (2 rx)`): its centre `kittenDotX` R to the kitten's right (the badge
    /// side is +1 for every kitten, so on the left side it points at the head) and `kittenDotY` R up, its radius `kittenDotR` R at most (the "!" circle, 0.3 R, times the
    /// badge's overshoot of 1.1 and the small badge's 1.25 below Ø28). `kittenRx` is the least rx a kitten has (latte and noodle, 1.04, times the kitten's 0.97), so R is never low.
    static let kittenDotX = 1.4, kittenDotY = -0.92, kittenDotR = 0.3 * 1.1 * 1.25, kittenRx = 1.04 * 0.97

    /// Where a kitten's circle, its state dot or the "+N" sits, in points relative to the head: the slots are in units of D.
    private static func shapes(_ slots: CatKittens.Slots, d: Double) -> (circles: [(x: Double, y: Double, r: Double)], dots: [(x: Double, y: Double, r: Double)], label: (x: Double, y: Double, halfW: Double, halfH: Double)?) {
        let circles = slots.shown.map { (x: $0.x * d, y: $0.y * d, r: $0.d * d / 2 * 1.1) }
        let dots = slots.shown.map { k -> (x: Double, y: Double, r: Double) in
            let R = k.d * d / (2 * kittenRx)
            return (k.x * d + kittenDotX * R, k.y * d + kittenDotY * R, kittenDotR * R)
        }
        guard let m = slots.moreAt else { return (circles, dots, nil) }
        let size = m.size * d, text = "+\(slots.more)", sz = max(8, size)
        return (circles, dots, (m.x * d, m.y * d, labelWidth(text, size) / 2, sz * 1.3 / 2))
    }

    /// The window for a cat of head width `d` with these kittens (`DesktopCatTrip.kittenSlots`, already mirrored for the side): the canvas, the hearts above and, on the
    /// kittens' side, as far as the last kitten's circle and state dot, or the "+N", reaches.
    static func frame(d: Double, slots: CatKittens.Slots) -> DesktopCatFrame {
        let half = d * canvasK / 2, top = half + d * heartsK
        var left = -half, right = half
        let s = shapes(slots, d: d)
        for c in s.circles + s.dots { left = min(left, c.x - c.r); right = max(right, c.x + c.r) }
        if let l = s.label { left = min(left, l.x - l.halfW); right = max(right, l.x + l.halfW) }
        return DesktopCatFrame(w: right - left, h: top + half, headX: -left, headY: top)
    }

    /// The side the kittens go on: the left (-1) when the cat is in the right half of its screen's visible frame, so they stay on the screen; else the right (1).
    static func side(of spot: DesktopSpot, screens: [DesktopScreen]) -> Int {
        let list = DesktopCatSpots.tidy(screens)
        guard let s = list.first(where: { DesktopCatSpots.contains($0.frame, spot) }) else { return 1 }
        return spot.x > s.visible.x + s.visible.w / 2 ? -1 : 1
    }

    /// Whether the mouse is on the cat's body: `p` is relative to the head (x right, y down). `badge` says the cat shows one.
    static func hits(_ p: DesktopSpot, d: Double, slots: CatKittens.Slots, badge: Bool) -> Bool {
        guard p.x.isFinite, p.y.isFinite else { return false }
        if hypot(p.x, p.y) <= d * headK { return true }
        if badge && hypot(p.x - d * badgeX, p.y - d * badgeY) <= d * badgeK { return true }
        let s = shapes(slots, d: d)
        if s.circles.contains(where: { hypot(p.x - $0.x, p.y - $0.y) <= $0.r }) { return true }
        if let l = s.label, abs(p.x - l.x) <= l.halfW, abs(p.y - l.y) <= l.halfH { return true }
        return false
    }

    /// The window's bottom-left corner in AppKit's coordinates, for a cat whose head centre is at `spot`.
    static func origin(spot: DesktopSpot, frame: DesktopCatFrame, primaryHeight: Double) -> (x: Double, y: Double) {
        let c = DesktopCatScreens.appKit(spot, primaryHeight: primaryHeight)
        return (c.x - frame.headX, c.y - (frame.h - frame.headY))
    }
}
