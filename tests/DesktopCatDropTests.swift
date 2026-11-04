import Foundation

@main
enum DesktopCatDropTests {
    typealias D = DesktopCatDrop
    static func spot(_ x: Double, _ y: Double) -> DesktopSpot { DesktopSpot(x: x, y: y) }

    @MainActor static func main() {
        let screens = DesktopCatSpots.screens([["frame": ["x": 0, "y": 0, "w": 1512, "h": 982], "visible": ["x": 0, "y": 37, "w": 1512, "h": 875], "main": true]])
        func decide(_ p: DesktopSpot, island: Bool = false, window: Bool = false, captured: Bool = false, store: Bool = false, size: DesktopSize = .medium) -> DesktopDrop {
            D.decide(point: p, screens: screens, size: size, onIsland: island, windowUnder: window, contextCaptured: captured, appStore: store)
        }

        CT.section("a drop on another app's window attaches it, exactly as today (the GitHub build)")
        CT.check("a window whose context was captured: attach", decide(spot(600, 400), window: true, captured: true), .attach)
        CT.check("a window whose context could not be captured: nothing happens and the cat stays home", decide(spot(600, 400), window: true, captured: false), .stayHome)
        CT.check("the same window on the island itself: still nothing", decide(spot(600, 20), island: true, window: true, captured: true), .stayHome)

        CT.section("a drop on empty desktop places the cat")
        CT.check("where it was dropped", decide(spot(600, 400)), .place(spot(600, 400)))
        CT.check("held where the cat may sit: not under the menu bar", decide(spot(600, 5)), .place(spot(600, 37 + 56)))
        CT.check("and not past the edge", decide(spot(1510, 980), size: .large), .place(spot(1512 - 72, 912 - 72)))
        CT.check("a drop on the island does nothing", decide(spot(756, 20), island: true), .stayHome)
        CT.check("a drop beside the screens goes to the default spot", decide(spot(9000, 9000)), .place(DesktopCatSpots.defaultSpot(screens, size: .medium)!))
        CT.check("a point that is NaN does nothing", decide(spot(.nan, 5)), .stayHome)
        CT.check("with no screen there is nowhere to sit", D.decide(point: spot(5, 5), screens: [], size: .medium, onIsland: false, windowUnder: false, contextCaptured: false, appStore: false), .stayHome)

        CT.section("the App Store build has no attach: any drop that is not on the island places the cat")
        CT.check("over a window", decide(spot(600, 400), window: true, captured: false, store: true), .place(spot(600, 400)))
        CT.check("even if a capture were claimed", decide(spot(600, 400), window: true, captured: true, store: true), .place(spot(600, 400)))
        CT.check("on empty desktop", decide(spot(600, 400), store: true), .place(spot(600, 400)))
        CT.check("on the island: nothing", decide(spot(756, 20), island: true, store: true), .stayHome)
        CT.finish()
    }
}
