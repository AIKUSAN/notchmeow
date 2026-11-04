import Foundation

@main
enum DesktopCatLayoutTests {
    typealias L = DesktopCatLayout
    typealias Sc = DesktopCatScreens
    typealias T = DesktopCatTrip

    static func spot(_ x: Double, _ y: Double) -> DesktopSpot { DesktopSpot(x: x, y: y) }
    static func kittens(_ n: Int) -> [CatKittens.Kitten] { (0..<n).map { CatKittens.Kitten(id: "k\($0)", state: .working, born: 0, last: 0) } }
    static func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> DesktopRect { DesktopRect(x: x, y: y, w: w, h: h) }

    @MainActor static func main() {
        // A MacBook with a monitor above it and one to its right, as AppKit reports them: the origin at the bottom left of the main screen.
        let laptop = Sc.AppKitScreen(frame: rect(0, 0, 1512, 982), visible: rect(0, 78, 1512, 875))   // the Dock at the bottom, the menu bar on top
        let right = Sc.AppKitScreen(frame: rect(1512, -100, 2560, 1440), visible: rect(1512, -100, 2560, 1415))

        CT.section("AppKit's screens become the contract's: y flips around the main screen's top edge")
        CT.check("the main screen's height", Sc.primaryHeight([laptop, right]), 982)
        let c = Sc.contract([laptop, right])
        CT.check("the laptop: frame at the top left, the menu bar's 29 pt and the Dock's 78 pt taken out of the visible frame", [c[0].frame, c[0].visible], [rect(0, 0, 1512, 982), rect(0, 29, 1512, 875)])
        CT.check("the monitor to its right: its bottom (AppKit y -100) is 100 pt below the laptop's, so its top is 258 pt above it", [c[1].frame, c[1].visible], [rect(1512, 982 - 1340, 2560, 1440), rect(1512, 982 - 1340 + 25, 2560, 1415)])
        CT.check("only the first is the main one", [c[0].main, c[1].main], [true, false])
        CT.check("the key of the arrangement is the contract's (the Dock moving does not change it)", DesktopCatSpots.screenKey(c), "0,0,1512,982|1512,-358,2560,1440")
        CT.check("no screens, no conversion", [Double(Sc.contract([]).count), Sc.primaryHeight([])], [0, 0])
        CT.check("a point both ways", [Sc.spot(fromAppKit: 100, 900, primaryHeight: 982), spot(100, 82)], [spot(100, 82), spot(100, 82)])
        let back = Sc.appKit(spot(100, 82), primaryHeight: 982)
        CT.check("and back", [back.x, back.y], [100, 900])
        CT.checkTrue("the cat sits where the contract's clamp says, on the laptop's visible frame", DesktopCatSpots.clampSpot(spot(5, 5), c, size: .medium) == spot(56, 29 + 56))

        CT.section("the window: the canvas, the hearts above, and the kittens on their side, and no larger")
        for size in DesktopSize.allCases {
            let d = size.d, half = d / 0.6 / 2
            let none = L.frame(d: d, slots: T.kittenSlots([], side: 1))
            CT.checkNear("\(size.rawValue): with no kittens the window is the canvas wide (\(d / 0.6))", none.w, d / 0.6)
            CT.checkNear("\(size.rawValue): and the canvas plus the hearts tall", none.h, d / 0.6 + d * 40 / 58, tol: 1e-9)
            CT.check("\(size.rawValue): the head is centred across and sits one canvas-half below the hearts", [none.headX, none.headY], [half, half + d * 40 / 58])
            for side in [1, -1] {
                for n in [1, 3, 4, 8] {
                    let slots = T.kittenSlots(kittens(n), side: side)
                    let f = L.frame(d: d, slots: slots)
                    let reach = slots.shown.map { abs($0.x) * d + $0.d * d / 2 * 1.1 }.max() ?? 0
                    let farSide = side == 1 ? f.w - f.headX : f.headX, nearSide = side == 1 ? f.headX : f.w - f.headX
                    CT.checkTrue("\(size.rawValue), \(n) kittens, side \(side): the window holds the last kitten, and is wider than the canvas only on the kittens' side", farSide >= reach - 1e-9 && abs(nearSide - half) < 1e-9 && abs(f.h - none.h) < 1e-9 && abs(f.headY - none.headY) < 1e-9)
                }
            }
            let four = T.kittenSlots(kittens(4), side: 1), f4 = L.frame(d: d, slots: four)
            CT.checkTrue("\(size.rawValue): the +N label is inside the window too", f4.w - f4.headX >= four.moreAt!.x * d + L.labelWidth("+1", four.moreAt!.size * d) / 2 - 1e-9)
            CT.checkTrue("\(size.rawValue): three kittens and a +N fit in under three heads' width beyond the canvas", L.frame(d: d, slots: T.kittenSlots(kittens(8), side: 1)).w < d / 0.6 + 2.2 * d)
        }

        CT.section("the window holds each kitten's drawn extent (its circle and its state dot) and the +N, at every size and side, and the head's canvas inside")
        for size in DesktopSize.allCases {
            let d = size.d, half = d / 0.6 / 2
            for side in [1, -1] {
                for n in [1, 2, 3, 5] {
                    let slots = T.kittenSlots(kittens(n), side: side)
                    let f = L.frame(d: d, slots: slots)
                    // The drawn boxes from the head centre (x right, y down), as [left, right, top, bottom]. A kitten's dot is CatGeometry's badge at rest: 1.4 R to the
                    // kitten's right and 0.92 R up, radius 0.3 R × 1.1 (its overshoot) × 1.25 (the small badge); R = D / (2 rx), with the least rx a kitten has (1.04 × 0.97).
                    var boxes: [[Double]] = []
                    for k in slots.shown {
                        let kx = k.x * d, ky = k.y * d, cr = k.d * d / 2 * 1.1
                        boxes.append([kx - cr, kx + cr, ky - cr, ky + cr])
                        let R = k.d * d / (2 * 1.04 * 0.97), dx = kx + 1.4 * R, dy = ky - 0.92 * R, dr = 0.3 * 1.1 * 1.25 * R
                        boxes.append([dx - dr, dx + dr, dy - dr, dy + dr])
                    }
                    if let m = slots.moreAt {
                        let hw = L.labelWidth("+\(slots.more)", m.size * d) / 2, hh = max(8, m.size * d) * 1.3 / 2
                        boxes.append([m.x * d - hw, m.x * d + hw, m.y * d - hh, m.y * d + hh])
                    }
                    let within = boxes.allSatisfy { $0[0] >= -f.headX - 1e-9 && $0[1] <= f.w - f.headX + 1e-9 && $0[2] >= -f.headY - 1e-9 && $0[3] <= f.h - f.headY + 1e-9 }
                    CT.checkTrue("\(size.rawValue), \(n) kittens, side \(side): every kitten's circle and dot, and the +N, are inside the window", within)
                    CT.checkTrue("\(size.rawValue), \(n) kittens, side \(side): the head's canvas is inside too", f.headX >= half - 1e-9 && f.w - f.headX >= half - 1e-9 && f.headY >= half - 1e-9 && f.h - f.headY >= half - 1e-9)
                }
            }
        }
        let smallD = DesktopSize.small.d, three = T.kittenSlots(kittens(3), side: 1)
        let oldRight = max(smallD / 0.6 / 2, three.shown.map { $0.x * smallD + $0.d * smallD / 2 * 1.1 }.max() ?? 0), oldW = oldRight + smallD / 0.6 / 2
        let newW = L.frame(d: smallD, slots: three).w
        CT.checkTrue("at Small with 3 kittens the window is wider than the old formula's: \(String(format: "%.2f", newW)) pt against \(String(format: "%.2f", oldW)) pt", newW > oldW + 1)

        CT.section("the window on the screen: its head is exactly on the spot")
        let f = L.frame(d: 64, slots: T.kittenSlots(kittens(2), side: 1))
        let o = L.origin(spot: spot(900, 300), frame: f, primaryHeight: 982)
        CT.checkNear("left of the window plus the head's offset is the spot's x", o.x + f.headX, 900)
        CT.checkNear("top of the window (AppKit's y up) minus the head's offset is the spot's AppKit y", o.y + f.h - f.headY, 982 - 300)

        CT.section("which side the kittens go on: left in the right half of the screen, so they stay on it")
        CT.check("the left half keeps them on the right", L.side(of: spot(300, 400), screens: c), 1)
        CT.check("the right half sends them to the left", L.side(of: spot(1300, 400), screens: c), -1)
        CT.check("the exact middle of the visible frame is still the left half", L.side(of: spot(756, 400), screens: c), 1)
        CT.check("on the monitor, its own halves count", [L.side(of: spot(1600, 400), screens: c), L.side(of: spot(3900, 400), screens: c)], [1, -1])
        CT.check("a spot on no screen has the default", L.side(of: spot(9000, 9000), screens: c), 1)
        CT.check("no screens, the default", L.side(of: spot(1, 1), screens: []), 1)

        CT.section("the body takes the mouse; everything else passes through")
        let d = 64.0, two = T.kittenSlots(kittens(2), side: 1), many = T.kittenSlots(kittens(8), side: 1), noKit = T.kittenSlots([], side: 1)
        CT.checkTrue("the middle of the head", L.hits(spot(0, 0), d: d, slots: noKit, badge: false))
        CT.checkTrue("just inside the head circle, and just outside", L.hits(spot(0.55 * d - 0.5, 0), d: d, slots: noKit, badge: false) && !L.hits(spot(0.55 * d + 0.5, 0), d: d, slots: noKit, badge: false))
        CT.checkTrue("the corners of the canvas pass through (the window is a square, the cat a circle)", !L.hits(spot(d / 0.6 / 2 - 1, d / 0.6 / 2 - 1), d: d, slots: noKit, badge: true) && !L.hits(spot(-d / 0.6 / 2 + 1, -d / 0.6 / 2 + 1), d: d, slots: noKit, badge: true))
        CT.checkTrue("the hearts' room above the cat passes through", !L.hits(spot(0, -d * 1.2), d: d, slots: noKit, badge: true))
        CT.checkTrue("the badge takes the mouse when there is one, and not when there is none", L.hits(spot(0.7 * d, -0.46 * d), d: d, slots: noKit, badge: true) && !L.hits(spot(0.7 * d, -0.46 * d), d: d, slots: noKit, badge: false))
        CT.checkTrue("a kitten takes it, the gap between two does not", L.hits(spot(0.82 * d, 0.22 * d), d: d, slots: two, badge: false) && L.hits(spot(1.15 * d, 0.22 * d), d: d, slots: two, badge: false) && !L.hits(spot(1.4 * d, 0.22 * d), d: d, slots: two, badge: false))
        CT.checkTrue("the third kitten's place is empty with two", !L.hits(spot(1.48 * d, 0.22 * d), d: d, slots: two, badge: false))
        CT.checkTrue("the +N label takes it", L.hits(spot(1.81 * d, 0.22 * d), d: d, slots: many, badge: false))
        CT.checkTrue("on the left the kittens are on the left", L.hits(spot(-0.82 * d, 0.22 * d), d: d, slots: T.kittenSlots(kittens(2), side: -1), badge: false) && !L.hits(spot(0.82 * d, 0.22 * d), d: d, slots: T.kittenSlots(kittens(2), side: -1), badge: false))
        CT.checkTrue("a point that is NaN is nowhere", !L.hits(spot(.nan, 0), d: d, slots: noKit, badge: true) && !L.hits(spot(0, .infinity), d: d, slots: noKit, badge: true))
        var inside = 0, total = 0
        let fr = L.frame(d: d, slots: many)
        for ix in stride(from: -fr.headX, through: fr.w - fr.headX, by: 2) { for iy in stride(from: -fr.headY, through: fr.h - fr.headY, by: 2) { total += 1; if L.hits(spot(ix, iy), d: d, slots: many, badge: true) { inside += 1 } } }
        CT.checkTrue("only a small part of the window is body (\(inside) of \(total) sample points): the rest is click-through", Double(inside) / Double(total) < 0.35 && inside > 0)
        CT.section("the badge takes the mouse only while it is drawn, at Small, Medium and Large")
        for size in DesktopSize.allCases {
            let bd = size.d, none = T.kittenSlots([], side: 1)
            let centre = spot(0.7 * bd, -0.46 * bd), near = spot(0.7 * bd + (0.2 * bd - 0.5), -0.46 * bd), beyond = spot(0.7 * bd - (0.2 * bd + 0.5), -0.46 * bd)
            CT.checkTrue("\(size.rawValue): the badge's centre and the point just inside its edge take the mouse while it is drawn", L.hits(centre, d: bd, slots: none, badge: true) && L.hits(near, d: bd, slots: none, badge: true))
            CT.checkTrue("\(size.rawValue): and pass through when no badge is drawn", !L.hits(centre, d: bd, slots: none, badge: false) && !L.hits(near, d: bd, slots: none, badge: false))
            CT.checkTrue("\(size.rawValue): a point just outside the badge's circle passes through either way", !L.hits(beyond, d: bd, slots: none, badge: true) && !L.hits(beyond, d: bd, slots: none, badge: false))
        }
        CT.finish()
    }
}
