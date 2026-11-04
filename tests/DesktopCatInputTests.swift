import Foundation

@main
enum DesktopCatInputTests {
    typealias C = DesktopCatClicks
    static func spot(_ x: Double, _ y: Double) -> DesktopSpot { DesktopSpot(x: x, y: y) }

    @MainActor static func main() {
        CT.section("a lone click acts only after the double-click interval")
        var c = C(interval: 0.5)
        CT.check("a press does nothing yet", c.down(at: 10, spot(5, 5)), [])
        CT.check("nor does the release: the click is waiting", c.up(at: 10.05, spot(5, 5)), [])
        CT.check("it waits until the interval after the release", c.waitUntil, 10.55)
        CT.check("the timer too early does nothing", c.timer(at: 10.3), [])
        CT.check("and on time it is a click", c.timer(at: 10.55), [.click])
        CT.check("only once", c.timer(at: 11), [])
        CT.check("nothing waits any more", c.waitUntil, nil)

        CT.section("a time that is not a number, during a wait and at rest")
        var n = C(interval: 0.5)
        CT.check("at rest, a press at a time that is not a number is an ordinary press", n.down(at: .nan, spot(5, 5)), [])
        CT.check("its release at a real time starts the wait", n.up(at: 60.2, spot(5, 5)), [])
        CT.check("the wait ends a double-click interval after that release", n.waitUntil, 60.7)
        CT.check("a press at a time that is not a number ends the wait: the click is delivered", n.down(at: .nan, spot(5, 5)), [.click])
        CT.check("and nothing waits any more: the new press is pending, not a click", n.waitUntil, nil)
        n = C(interval: 0.5)
        CT.check("a timer at a time that is not a number at rest does nothing", n.timer(at: .nan), [])
        _ = n.down(at: 70, spot(5, 5)); _ = n.up(at: 70.05, spot(5, 5))
        CT.check("a timer at a time that is not a number ends the wait: a click", n.timer(at: .nan), [.click])
        CT.check("only once", n.timer(at: 71), [])
        n = C(interval: 0.5)
        _ = n.down(at: 80, spot(5, 5))
        CT.check("a release at a time that is not a number does not click at once", n.up(at: .nan, spot(5, 5)), [])
        CT.checkTrue("it still ends: a later finite timer delivers the click, and nothing waits any more", { var m = n; return m.timer(at: 90) == [.click] && m.waitUntil == nil }())

        CT.section("a double-click sends it home and never also clicks")
        c = C(interval: 0.5)
        _ = c.down(at: 20, spot(5, 5)); _ = c.up(at: 20.05, spot(5, 5))
        CT.check("the second press inside the interval", c.down(at: 20.3, spot(5, 5)), [])
        CT.check("its release is the double-click", c.up(at: 20.35, spot(5, 5)), [.doubleClick])
        CT.check("the pending click is gone: the timer does nothing", c.timer(at: 21), [])
        _ = c.down(at: 30, spot(5, 5)); _ = c.up(at: 30.05, spot(5, 5))
        CT.check("a second press after the interval is a new click and the first one is delivered first", c.down(at: 31, spot(5, 5)), [.click])
        CT.check("and that one is waiting in its turn", c.up(at: 31.05, spot(5, 5)), [])
        CT.check("a double-click interval that is not a number is half a second", C(interval: .nan).interval, 0.5)

        CT.section("a drag moves it and never clicks")
        c = C(interval: 0.5)
        _ = c.down(at: 40, spot(100, 100))
        CT.check("4 points or less is still a press", c.dragged(spot(102, 103)), [])
        CT.check("past 4 points the drag begins, with the first move", c.dragged(spot(110, 100)), [.dragBegan, .dragMoved(spot(110, 100))])
        CT.check("it follows", c.dragged(spot(120, 130)), [.dragMoved(spot(120, 130))])
        CT.check("the release ends it where the mouse is", c.up(at: 41, spot(125, 135)), [.dragEnded(spot(125, 135))])
        CT.check("no click comes later", c.timer(at: 42), [])
        CT.check("a release or a drag with no press does nothing", [c.up(at: 43, spot(1, 1)), c.dragged(spot(1, 1))], [[], []])
        c = C(interval: 0.5)
        _ = c.down(at: 50, spot(0, 0)); _ = c.up(at: 50.1, spot(0, 0)); _ = c.down(at: 50.2, spot(0, 0))
        CT.check("the second press of a double-click can still turn into a drag", c.dragged(spot(30, 0)), [.dragBegan, .dragMoved(spot(30, 0))])
        CT.check("and then it is only a drag", c.up(at: 50.5, spot(30, 0)), [.dragEnded(spot(30, 0))])

        CT.section("the right-click menu")
        let m = DesktopCatMenu.entries(size: .medium, shortcut: "⌃⌥D")
        CT.check("Open the notch, Send home, Size and the shortcut's line", m.count, 6)
        CT.check("the first two", [m[0], m[1]], [.action(title: "Open the notch", .openNotch, checked: false), .action(title: "Send home", .sendHome, checked: false)])
        if case .submenu(let title, let sizes) = m[3] {
            CT.check("the Size menu", title, "Size")
            CT.check("with the current size ticked", sizes, [.action(title: "Small", .size(.small), checked: false), .action(title: "Medium", .size(.medium), checked: true), .action(title: "Large", .size(.large), checked: false)])
        } else { CT.checkTrue("the fourth entry is the Size menu", false) }
        CT.check("the last line shows the shortcut", m[5], .note("Out or home: ⌃⌥D"))
        CT.check("with no shortcut (off, or the platform has none) there is no line", DesktopCatMenu.entries(size: .large, shortcut: nil).count, 4)
        CT.check("and an empty shortcut is none", DesktopCatMenu.entries(size: .small, shortcut: "").count, 4)
        CT.check("the Wardrobe submenu is not there unless the caller gives the stored choice (the menu as H shipped it)", DesktopCatMenu.entries(size: .medium, shortcut: "⌃⌥D", outfit: nil), m)
        let dressed = DesktopCatMenu.entries(size: .medium, shortcut: "⌃⌥D", outfit: "bow", autoToday: "witchhat")
        CT.check("with it: Open the notch, Send home, Size, Wardrobe and the shortcut's line, in that order", dressed.count, 7)
        if case .submenu(let title, let items) = dressed[4] {
            CT.check("the Wardrobe menu", title, "Wardrobe")
            let choices = items.compactMap { e -> (String, String, Bool)? in if case .action(let t, .outfit(let id), let c) = e { return (id, t, c) } else { return nil } }
            CT.check("holds the 18 choices in the grid's order", choices.map(\.0), Wardrobe.ids)
            CT.check("with the stored one ticked and nothing else", choices.filter(\.2).map(\.0), ["bow"])
            CT.check("Auto's label shows today's result", choices[0].1, "Auto: today, Witch hat")
            CT.check("the groups' headings are greyed notes and the groups are set apart", [items.filter { if case .note = $0 { return true } else { return false } }.count, items.filter { $0 == .separator }.count], [4, 4])
        } else { CT.checkTrue("the fifth entry is the Wardrobe menu", false) }
        CT.check("and the shortcut's line is still last", dressed[6], .note("Out or home: ⌃⌥D"))

        CT.section("kittens in motion for 600 ms after any change to the list, and the notch spot")
        func k(_ id: String, _ state: CatKittens.State = .working) -> CatKittens.Kitten { CatKittens.Kitten(id: id, state: state, born: 0, last: 0) }
        var w = DesktopKittenWatch()
        CT.check("no kittens, nothing changed", w.observe([], now: 1000), false)
        CT.check("a kitten arrives: motion", w.observe([k("a")], now: 2000), true)
        CT.check("still, 599 ms later", w.observe([k("a")], now: 2599), true)
        CT.check("at 600 ms it is over", w.observe([k("a")], now: 2600), false)
        CT.check("a kitten state change that is not a leave is not a change of the list", w.observe([k("a", .searching)], now: 5000), false)
        CT.check("a second one arrives: motion again", w.observe([k("a"), k("b")], now: 6000), true)
        CT.check("one starts to leave: the list changed", w.observe([k("a"), k("b", .leaving)], now: 7000), true)
        CT.check("and goes: it changed once more", w.observe([k("a")], now: 7400), true)
        CT.check("quiet again 600 ms later", w.observe([k("a")], now: 8000), false)
        CT.check("the last one goes: motion, then none", [w.observe([], now: 9000), w.observe([], now: 9700)], [true, false])
        CT.check("a clock that is not a number is not motion, and changes nothing", [w.observe([k("z")], now: .nan), w.observe([k("z")], now: 20000)], [false, true])
        CT.check("a clock that goes backwards is not motion", w.observe([k("z")], now: 19000), false)
        let screen = DesktopRect(x: 0, y: 0, w: 1512, h: 982)
        CT.check("the notch spot is the island's left edge plus the cat's x, on the screen's top", DesktopCatLayout.notchSpot(screenFrame: screen, islandW: 200, cx: 50, cy: 15), spot(756 - 100 + 50, 15))
        CT.check("on a second screen it follows that screen", DesktopCatLayout.notchSpot(screenFrame: DesktopRect(x: 1512, y: -358, w: 2560, h: 1440), islandW: 200, cx: 50, cy: 15), spot(1512 + 1280 - 100 + 50, -343))
        CT.finish()
    }
}
