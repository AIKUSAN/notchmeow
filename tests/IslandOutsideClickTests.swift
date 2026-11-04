import CoreGraphics
import Foundation

// The rules of the outside click (IslandOutsideClick.swift): when the open island folds, and when it stays.

@main
enum IslandOutsideClickTests {
    static func main() {
        var passed = 0
        func ok(_ cond: Bool, _ name: String) { precondition(cond, name); passed += 1; print("✓ \(name)") }

        typealias C = IslandOutsideClick.Context
        let open = C(expanded: true, pinned: false, held: false, typing: false, pointerInIsland: false, busy: false)
        ok(IslandOutsideClick.shouldFold(open), "an open, unpinned island with nothing waiting folds on a click outside")

        func with(_ edit: (inout C) -> Void) -> C { var c = open; edit(&c); return c }
        ok(!IslandOutsideClick.shouldFold(with { $0.expanded = false }), "a compact or hidden island is never folded by a click (there is nothing to fold)")
        ok(!IslandOutsideClick.shouldFold(with { $0.pinned = true }), "a pinned island (⌘P) stays")
        ok(!IslandOutsideClick.shouldFold(with { $0.held = true }), "a waiting permission request, question, chat card or the shelf's hold keeps the island")
        ok(!IslandOutsideClick.shouldFold(with { $0.typing = true }), "typing in the chat keeps the island")
        ok(!IslandOutsideClick.shouldFold(with { $0.pointerInIsland = true }), "a click with the pointer over the island is not outside")
        ok(!IslandOutsideClick.shouldFold(with { $0.busy = true }), "a cat drag or the Wardrobe menu keeps the island")
        // Every pair of reasons to stay still stays.
        let reasons: [(inout C) -> Void] = [{ $0.pinned = true }, { $0.held = true }, { $0.typing = true }, { $0.pointerInIsland = true }, { $0.busy = true }]
        for (i, a) in reasons.enumerated() { for b in reasons[(i + 1)...] { ok(!IslandOutsideClick.shouldFold(with { a(&$0); b(&$0) }), "two reasons to stay (\(i))") } }

        var t = IslandOutsideClick.Tracker()
        t.down(at: CGPoint(x: 100, y: 100))
        ok(t.up(at: CGPoint(x: 102, y: 101)), "a press and release 2 pt apart is a click")
        t.down(at: CGPoint(x: 100, y: 100))
        ok(!t.up(at: CGPoint(x: 100, y: 120)), "a press dragged 20 pt (a file taken from Finder, a window moved) is not a click")
        ok(!t.up(at: CGPoint(x: 100, y: 100)), "a release with no press seen is not a click, and the press is forgotten after each release")
        t.down(at: CGPoint(x: 0, y: 0))
        ok(t.up(at: CGPoint(x: 3, y: 2)), "3.6 pt is still a click")
        t.down(at: CGPoint(x: 0, y: 0))
        t.reset()
        ok(!t.up(at: CGPoint(x: 0, y: 0)), "a reset forgets the press")

        print("Island outside click: \(passed) checks passed")
    }
}
