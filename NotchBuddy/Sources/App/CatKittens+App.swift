import Foundation
import QuartzCore

// The app's way into the kittens: each agent pill's list in `AppState`, the clock the events are stamped with, and the sleep timer's sweep. Nothing here is in the
// contract, and the test programs do not compile this file (`tests/CatWiringTests.swift` pins where the hook server and the sleep clock call it).

extension AppState {
    /// Applies one kitten event to a pill's list (`CatKittens.step`). A pill with no kittens left has no entry. Never stored.
    func kittenEvent(_ pillId: String, _ event: CatKittens.Event) {
        let next = CatKittens.step(kittens[pillId] ?? [], event)
        if next.isEmpty { if kittens[pillId] != nil { kittens[pillId] = nil } } else if kittens[pillId] != next { kittens[pillId] = next }
    }

    /// The cat's ten-minute sleep timer fired: a kitten whose stop never came, and whose last event is ten minutes old, goes (`CatKittens.step`'s sweep).
    func sweepKittens(at ms: Double = CACurrentMediaTime() * 1000) {
        for pill in Array(kittens.keys) { kittenEvent(pill, .sweep(t: ms)) }
    }

    /// What to draw for a pill's kittens at `ms`: the list in order, without a farewell that is over. Called from the canvases, which redraw on their own: no timer is needed.
    func kittenView(_ pillId: String, at ms: Double = CACurrentMediaTime() * 1000) -> [CatKittens.Kitten] {
        CatKittens.view(kittens[pillId] ?? [], now: ms)
    }
}
