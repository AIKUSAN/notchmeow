import Foundation

// The compact island's two wings: their rectangles, when the island can step aside, the swoosh's numbers and the fold's timing, as plain numbers and a fake clock.
// Run it through scripts/test-island-wing.sh.

@main
enum IslandWingTests {
    /// One tick on the fake clock, with the defaults of a plain hover.
    @MainActor static func tick(_ y: inout IslandWing.Yield, _ t: Double, _ zone: IslandWing.Zone?, active: Bool = true, button: Bool = false) -> IslandWing.Yield.Out {
        y.step(now: t, zone: zone, active: active, buttonDown: { button })
    }

    @MainActor static func main() {
        CT.section("the numbers the owner chose")
        CT.checkNear("the cats, grid and badges fade out in 0.15 s as the island shrinks", IslandWing.fadeOut, 0.15)
        CT.checkNear("and the island swooshes back out 1 s after the pointer has left both wings", IslandWing.returnDelay, 1.0)
        CT.checkTrue("it fades back in no faster than it went out, and well within the delay", IslandWing.fadeIn >= IslandWing.fadeOut && IslandWing.fadeIn < IslandWing.returnDelay)
        CT.checkNear("the swoosh is a spring of about 0.22 s", IslandWing.springResponse, 0.22)
        CT.checkTrue("with a slight overshoot: a damping fraction under 1, and not wobbly", IslandWing.springDamping < 1 && IslandWing.springDamping > 0.5)

        CT.section("the two wings: the parts beside the notch")
        // A notch screen: the panel is 720 wide, the island 344 (notch 184 plus two wings of 80) by 32, at the top of a panel 320 high (AppKit: y up).
        let island = CGRect(x: 188, y: 288, width: 344, height: 32)
        let w = IslandWing.wings(island: island, notchWidth: 184)
        CT.check("the left wing runs from the island's left edge to the notch's left edge", [w.left.minX, w.left.maxX], [188, 268])
        CT.check("the right wing from the notch's right edge to the island's right edge", [w.right.minX, w.right.maxX], [452, 532])
        CT.check("both are the strip's height", [w.left.minY, w.left.maxY, w.right.minY, w.right.maxY], [288, 320, 288, 320])
        CT.checkTrue("the notch (the island's middle) is in neither: it is the hover-open zone", !w.contains(CGPoint(x: 360, y: 300)) && !w.contains(CGPoint(x: 268.1, y: 300)) && !w.contains(CGPoint(x: 451.9, y: 300)))
        CT.checkTrue("the first and last points of each wing are in it", w.contains(CGPoint(x: 188, y: 300)) && w.contains(CGPoint(x: 267.9, y: 300)) && w.contains(CGPoint(x: 452, y: 300)) && w.contains(CGPoint(x: 531.9, y: 300)))
        let slopped = IslandWing.wings(island: island, notchWidth: 184, slop: 6)
        CT.check("with the 6 pt hover slop each wing reaches 6 pt further out, up and down, and not towards the notch", [slopped.left.minX, slopped.left.maxX, slopped.right.minX, slopped.right.maxX, slopped.left.minY, slopped.right.maxY], [182, 268, 452, 538, 282, 326])
        let bar = IslandWing.wings(island: CGRect(x: 240, y: 296, width: 240, height: 24), notchWidth: 80)
        CT.check("a screen without a notch: the same rule, around its 80 pt bar", [bar.left.width, bar.right.width, bar.right.height], [80, 80, 24])
        let none = IslandWing.wings(island: CGRect(x: 100, y: 0, width: 50, height: 30), notchWidth: 184)
        CT.check("an island narrower than its notch has no wing at all", [none.left.width, none.right.width], [0, 0])

        CT.section("what the island folds to")
        CT.check("the notch's own width", IslandWing.foldedWidth(notchWidth: 184), 184)
        CT.check("at rest it is the full width", IslandWing.width(full: 344, notchWidth: 184, swoosh: 0), 344)
        CT.check("folded it is the notch's", IslandWing.width(full: 344, notchWidth: 184, swoosh: 1), 184)
        CT.check("half way it is half way", IslandWing.width(full: 344, notchWidth: 184, swoosh: 0.5), 264)

        CT.section("when the island can step aside")
        CT.checkTrue("in the compact island with nothing wanting it", IslandWing.isActive(compact: true, greetingTail: false, dragging: false, alert: false))
        CT.checkTrue("not hidden or expanded (compact is false there)", !IslandWing.isActive(compact: false, greetingTail: false, dragging: false, alert: false))
        CT.checkTrue("not while the greeting's tail draws the session cats", !IslandWing.isActive(compact: true, greetingTail: true, dragging: false, alert: false))
        CT.checkTrue("not while the cat's head is being dragged", !IslandWing.isActive(compact: true, greetingTail: false, dragging: true, alert: false))
        CT.checkTrue("not while an alert wants the island (a request, a question, a file, the desktop cat, the shelf)", !IslandWing.isActive(compact: true, greetingTail: false, dragging: false, alert: true))

        CT.section("the fold: in at once, out one second after the pointer has left both wings")
        var y = IslandWing.Yield()
        CT.check("the pointer elsewhere: nothing happens", tick(&y, 0, nil), .init(faded: false, passThrough: false))
        CT.check("the pointer reaches a wing: the island folds and the mouse passes through on that very tick", tick(&y, 1.0, .right), .init(faded: true, passThrough: true))
        CT.check("it stays while the pointer stays (ten seconds)", tick(&y, 11.0, .right), .init(faded: true, passThrough: true))
        CT.check("the pointer leaves: the island is still folded, and the mouse is no longer passed on", tick(&y, 12.0, nil), .init(faded: true, passThrough: false))
        CT.check("0.9 s later it is still folded", tick(&y, 12.9, nil), .init(faded: true, passThrough: false))
        CT.check("1 s after the pointer was first seen away it swooshes back out", tick(&y, 13.0, nil), .init(faded: false, passThrough: false))
        CT.check("and stays", tick(&y, 20.0, nil), .init(faded: false, passThrough: false))

        CT.section("the left wing (the big cat) folds the island only after the pointer has rested there 0.4 s with no button pressed; the right wing folds it at once")
        CT.checkNear("the left dwell is 0.4 s", IslandWing.leftDwell, 0.4)
        y = IslandWing.Yield()
        CT.check("the pointer reaches the left wing: nothing yet", tick(&y, 5.0, .left), .init(faded: false, passThrough: false))
        CT.check("399 ms later: still nothing", tick(&y, 5.399, .left), .init(faded: false, passThrough: false))
        CT.check("400 ms after it arrived: the island folds, and the mouse passes through", tick(&y, 5.4, .left), .init(faded: true, passThrough: true))
        CT.check("it stays while the pointer stays", tick(&y, 9.0, .left), .init(faded: true, passThrough: true))
        y = IslandWing.Yield()
        _ = tick(&y, 1.0, .left)
        CT.check("a press at 200 ms cancels the dwell (a quick click, the drag out to the desktop, a right-click on the big cat)", tick(&y, 1.2, .left, button: true), .init(faded: false, passThrough: false))
        CT.check("the button released at 400 ms: the dwell starts over, it does not fold", tick(&y, 1.4, .left), .init(faded: false, passThrough: false))
        CT.check("399 ms after the release: still nothing", tick(&y, 1.799, .left), .init(faded: false, passThrough: false))
        CT.check("400 ms after the release: it folds", tick(&y, 1.8, .left), .init(faded: true, passThrough: true))
        y = IslandWing.Yield()
        _ = tick(&y, 0, .left)
        _ = tick(&y, 0.3, nil)
        CT.check("leaving the wing before the dwell is over cancels it, and coming back starts again from zero", tick(&y, 0.5, .left), .init(faded: false, passThrough: false))
        CT.check("(0.399 s after coming back: nothing)", tick(&y, 0.899, .left), .init(faded: false, passThrough: false))
        CT.check("(and the full 0.4 s: it folds)", tick(&y, 0.9, .left), .init(faded: true, passThrough: true))
        y = IslandWing.Yield()
        CT.check("the right wing needs no dwell: the grid folds the island on the first tick", tick(&y, 0, .right), .init(faded: true, passThrough: true))
        var held = IslandWing.Yield()
        for t in stride(from: 0.0, through: 3.0, by: 0.1) { _ = tick(&held, t, .left, button: true) }
        CT.check("a button held the whole time over the left wing never folds it", tick(&held, 3.1, .left, button: true), .init(faded: false, passThrough: false))
        var lazy = IslandWing.Yield()
        var leftAsked = 0
        for i in 0..<20 { _ = lazy.step(now: Double(i) * 0.01, zone: i < 10 ? nil : .left, active: true, buttonDown: { leftAsked += 1; return false }) }
        CT.check("the button is asked only while the pointer is on the left wing", leftAsked, 10)
        var folded = IslandWing.Yield()
        _ = tick(&folded, 0, .right)
        var askedFolded = 0
        for i in 1..<10 { _ = folded.step(now: Double(i), zone: .left, active: true, buttonDown: { askedFolded += 1; return false }) }
        CT.check("once folded, the left wing asks nothing and keeps the fold", askedFolded, 0)

        CT.section("both wings are one hover: going from one wing to the other (through the notch) keeps the fold, and the second starts again")
        y = IslandWing.Yield()
        _ = tick(&y, 0, .right)             // the left wing
        _ = tick(&y, 5.0, nil)          // crossing the notch
        CT.check("back in a wing (the other one) at 5.8 s: still folded, the mouse passes", tick(&y, 5.8, .right), .init(faded: true, passThrough: true))
        _ = tick(&y, 6.0, nil)
        CT.check("away again at 6.0 s: 0.9 s later it is still folded (the count began again)", tick(&y, 6.9, nil), .init(faded: true, passThrough: false))
        CT.check("and out again at 7.0 s", tick(&y, 7.0, nil), .init(faded: false, passThrough: false))

        CT.section("the mouse button held: a file dragged in, or a click that began elsewhere")
        y = IslandWing.Yield()
        CT.check("a button held when the pointer arrives never starts a fold: the wing is the island's, as before", tick(&y, 0, .right, button: true), .init(faded: false, passThrough: false))
        CT.check("and releasing it over the wing then folds it", tick(&y, 0.1, .right), .init(faded: true, passThrough: true))
        CT.check("a button pressed over a folded island leaves it folded", tick(&y, 0.2, .right, button: true), .init(faded: true, passThrough: true))

        CT.section("an alert cancels the step-aside at once, and a compact island that is not active never folds")
        y = IslandWing.Yield()
        _ = tick(&y, 0, .right)
        CT.check("an alert arrives (a permission card, a question, a file drop, the desktop cat's return): the island is back at once", tick(&y, 0.5, .right, active: false), .init(faded: false, passThrough: false))
        CT.check("and the pointer still over the wing while the alert lasts folds nothing", tick(&y, 0.6, .right, active: false), .init(faded: false, passThrough: false))
        CT.check("when the alert is over and the pointer is still over the wing, a new fold begins", tick(&y, 0.7, .right), .init(faded: true, passThrough: true))
        y = IslandWing.Yield()
        var asked = 0
        _ = y.step(now: 0, zone: nil, active: true, buttonDown: { asked += 1; return false })
        CT.check("with the pointer away the mouse button is never asked about", asked, 0)
        _ = y.step(now: 1, zone: .right, active: true, buttonDown: { asked += 1; return false })
        _ = y.step(now: 2, zone: .right, active: true, buttonDown: { asked += 1; return false })
        CT.check("it is asked once, when the fold begins, not on every tick after", asked, 1)
        var buttonAsked = 0
        var quiet = IslandWing.Yield()
        for i in 0..<50 { _ = quiet.step(now: Double(i), zone: i % 2 == 0 ? .right : nil, active: false, buttonDown: { buttonAsked += 1; return false }) }
        CT.check("an island that is not active never asks about the mouse button (a hidden island's slow poll costs nothing)", buttonAsked, 0)

        CT.section("a clock that is not a time")
        var odd = IslandWing.Yield()
        _ = tick(&odd, 0, .right)
        CT.check("NaN resets the island without a crash", tick(&odd, .nan, .right), .init(faded: false, passThrough: false))
        CT.check("infinity too", tick(&odd, .infinity, .right), .init(faded: false, passThrough: false))
        CT.check("and the next real tick works", tick(&odd, 3, .right), .init(faded: true, passThrough: true))
        _ = tick(&odd, 4, nil)
        CT.check("a clock that runs backwards does not bring the island back early", tick(&odd, 1, nil), .init(faded: true, passThrough: false))

        CT.section("fuzz: 20000 ticks that must keep the rules")
        var rng = SystemRandomNumberGenerator()
        var f = IslandWing.Yield(), t = 0.0, broke = 0, lastIn = -100.0, wasFaded = false
        for _ in 0..<20000 {
            t += Double.random(in: 0...0.05, using: &rng)
            let pick = Double.random(in: 0...1, using: &rng), zone: IslandWing.Zone? = pick < 0.15 ? .left : pick < 0.3 ? .right : nil, inWing = zone != nil, active = Double.random(in: 0...1, using: &rng) < 0.95
            let out = tick(&f, t, zone, active: active, button: Double.random(in: 0...1, using: &rng) < 0.05)
            if out.passThrough && !out.faded { broke += 1 }                                  // pass-through is only ever on a folded island
            if !active && out.faded { broke += 1 }                                           // an inactive island never keeps a fold
            if out.passThrough && !inWing { broke += 1 }                                     // and only with the pointer over a wing
            if active && inWing && out.faded { lastIn = t }
            if active && !inWing && wasFaded && !out.faded && t - lastIn < IslandWing.returnDelay { broke += 1 }   // never back early
            wasFaded = active && out.faded
        }
        CT.check("no tick broke a rule", broke, 0)

        CT.finish()
    }
}
