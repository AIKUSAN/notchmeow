import SwiftUI

// Focus awareness, the views (the spec docs/superpowers/specs/2026-10-17-focus-awareness-design.md, "The island (Mac)"): the still amber dot that says a session waits in its own
// app, and the read-only note under the card's ticker. Both read the marks at draw time (`FocusAware.Marks`, aged by `FocusAwareApp.now()`): no timer, no animation, no tap.
// The badge (`PillBadgeView`) wins over the dot and a waiting card wins over both (`FocusAware.showsDot`). The wording is `FocusAware.noteText`.

/// The theme's approval amber (the same colour as the pill's badge), read once for the dot and the note.
private let amber = Color(hex: Theme.State.color["approval"] ?? "#F5A524")

/// The amber dot. `ring` is the open island's: a dark ring 2 pt wider behind it, so it reads apart from the pill's own colours.
struct FocusWaitDot: View {
    let size: CGFloat
    var ring: Bool = false

    var body: some View {
        ZStack {
            if ring {
                Circle().fill(Color(hex: "#0B0C0E")).frame(width: size + 2, height: size + 2)
            }
            Circle().fill(amber).frame(width: size, height: size)
        }
    }
}

/// The read-only line "Waiting in <host>: <words>" on a card. No button, no tap of its own: the pill's tap still brings the app forward.
struct FocusWaitNote: View {
    let mark: FocusAware.Mark
    let leading: CGFloat

    var body: some View {
        Text(FocusAware.noteText(host: mark.host, words: mark.words))
            .font(.system(size: 11))
            .foregroundColor(amber)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.leading, leading)
            .padding(.trailing, 12)
            .padding(.top, 2)
    }
}

/// The compact notch's dots: one on the big cat and one on cat 2 (Two cats mode), each only while its pill has a live mark and no badge or waiting card. Nothing for the
/// big cat while the desktop cat is out (its spot is empty). Drawn from the cats' own spots (`CatIslandLayout.compactX`), 5 pt, no animation, no hit area.
struct FocusWaitCompactDots: View {
    @ObservedObject var state: AppState
    let islandW: CGFloat
    let islandH: CGFloat

    var body: some View {
        let layout = IslandRestingLayout(width: islandW, height: islandH)
        let d = layout.botDiameter
        let xs = CatIslandLayout.compactX(state.displayMode)
        let y = layout.botCenterY - d * 0.42
        ZStack(alignment: .topLeading) {
            if !state.desktopPhase.notchEmpty, let pill = state.cast.big.pill, state.focusDot(pill) {
                FocusWaitDot(size: 5).position(x: CGFloat(xs[0]) + d * 0.42, y: y)
            }
            if xs.count > 1, let pill = state.cast.second?.pill, state.focusDot(pill) {
                FocusWaitDot(size: 5).position(x: CGFloat(xs[1]) + d * 0.42, y: y)
            }
        }
        .frame(width: islandW, height: islandH, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

extension AppState {
    /// The amber dot on this pill: a live mark, and neither the pill's badge nor a waiting card on it (`FocusAware.showsDot`). Read at draw time.
    @MainActor func focusDot(_ pillId: String) -> Bool {
        FocusAware.showsDot(markLive: focusMarks.forPill(pillId, now: FocusAwareApp.now()) != nil,
                            badgeShown: tasks.first { $0.id == pillId }?.pillBadge != nil,
                            cardWaiting: cardWaiting(on: pillId))
    }
}
