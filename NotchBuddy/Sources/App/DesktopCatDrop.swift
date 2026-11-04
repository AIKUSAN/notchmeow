import Foundation

// What happens when the big cat is let go after a drag from the notch (sub-project H). Today a drop on another app's window attaches that window to a chat; H adds one more
// outcome, a drop on empty desktop places the cat there. The rule is pure so it can be tested: attaching must keep working exactly as it does today. Foundation only.

enum DesktopDrop: Equatable, Sendable {
    /// Another app's window is under the cat and its context was captured: attach it to the chat, as before.
    case attach
    /// Empty desktop: the cat lives here, at the clamped spot.
    case place(DesktopSpot)
    /// Nothing happens and the cat stays in the notch: the drop was on the island, on a window that could not be attached, or there is no screen to sit on.
    case stayHome
}

enum DesktopCatDrop {
    /// `point` is the cat's head in the contract's coordinates, `windowUnder` that another app's window is there (`windowBoundsAtScreenPoint`), `contextCaptured` that attaching
    /// it worked (`windowContextAtPoint`, only asked when `windowUnder`), and `onIsland` that the point is on the island itself. The App Store build has no attach, and so any
    /// drop that is not on the island places the cat there.
    static func decide(point: DesktopSpot, screens: [DesktopScreen], size: DesktopSize, onIsland: Bool, windowUnder: Bool, contextCaptured: Bool, appStore: Bool) -> DesktopDrop {
        if onIsland { return .stayHome }
        if !appStore && windowUnder { return contextCaptured ? .attach : .stayHome }
        guard let spot = DesktopCatSpots.clampSpot(point, screens, size: size), DesktopCatSpots.isValid(point) else { return .stayHome }
        return .place(spot)
    }
}
