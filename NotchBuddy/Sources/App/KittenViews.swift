import SwiftUI
import QuartzCore

// Kittens on the island: a transparent layer over a parent that draws that parent's kittens (`CatKittenDraw`), in the place `CatKittens.placeOf` says. A layer redraws with
// the canvas it is, so a farewell ends when `AppState.kittenView` stops listing the kitten: there is no timer, and a hidden island pauses it like every other cat.

/// One parent's kittens in one place. `pills` are the pills whose kittens it draws (the pair's compact label counts both cats'), `parentCat` the coat they are kittens of,
/// `unit` the parent's head width (a pill's height for `pill`).
struct KittenLayerView: View {
    @ObservedObject var state: AppState
    let pills: [String]
    let parentCat: String
    let place: String
    let unit: CGFloat
    let colour: String?
    @StateObject private var herd = CatKittenHerd()
    /// Set when the layer has nothing left to draw: it then stops asking for frames until the kittens, or the pills it draws, change. A leaving kitten stays in its list until the next event, and the list
    /// is what keeps the layer on the island, so without this an empty layer drew nothing at 30 fps for as long as the island was open and the cat awake.
    @State private var quiet = false

    var body: some View {
        let box = CatIslandLayout.kittenBox(place), u = Double(unit)
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: state.mode == .hidden || quiet)) { timeline in
            Canvas { context, size in
                _ = timeline.date   // the Canvas redraws on every tick of the timeline
                let now = CACurrentMediaTime() * 1000
                let list = pills.flatMap { state.kittenView($0, at: now) }
                herd.lastFrameEmpty = list.isEmpty
                let slots = CatKittens.slots(place, list)
                context.withCGContext { cg in
                    CatKittenDraw.draw(cg, slots, parentCat: parentCat, origin: (-box.x0 * u, -box.y0 * u), unit: u, colour: colour, dpr: Double(context.environment.displayScale), herd: herd,
                                       now: { CACurrentMediaTime() * 1000 }) { e in e.update(dt: CatEngine.frameDelta(now: CACurrentMediaTime(), last: e.lastTime)) }
                }
            }
            .onChange(of: timeline.date) { _, _ in
                if CatKittens.mayStop(lastFrameEmpty: herd.lastFrameEmpty, lists: pills.map { state.kittens[$0] ?? [] }, now: CACurrentMediaTime() * 1000) { quiet = true }
            }
        }
        .frame(width: (box.x1 - box.x0) * u, height: (box.y1 - box.y0) * u)
        .allowsHitTesting(false)
        .onChange(of: state.kittens) { _, _ in quiet = false }
        .onChange(of: pills) { _, _ in quiet = false }
    }
}

/// The kittens beside the big cat and cat 2 in the compact island and in the overview (the other views draw no kittens). Nothing is drawn, and nothing runs, while no agent has one.
struct KittenPlacement: View {
    @ObservedObject var state: AppState
    let islandW: CGFloat
    let islandH: CGFloat
    /// The Claude-only card's kittens are its project's subagents: a pill click changes them, so the placement redraws for the model too (P-mac).
    @ObservedObject private var projects = ProjectsModel.shared

    var body: some View {
        // While a project's peek is open over the left card the kittens step aside with the big cat (opacity only).
        layers
            .opacity(state.projectPeeking ? 0 : 1)
            .animation(.easeOut(duration: 0.12), value: state.projectPeeking)
    }

    @ViewBuilder private var layers: some View {
        let cast = state.cast
        let compact = state.mode == .compact, overview = state.mode == .expanded && state.view == .overview
        if overview, let rows = state.projectKittens {
            // The Claude-only card (Projects): the big card project's subagents replace the big cat's own kittens, which are the focused pill's (never both). Nothing is drawn while the
            // big cat is on the desktop, as for its own kittens.
            if !state.desktopPhase.notchEmpty {
                let one = botPosition(mode: state.mode, view: state.view, islandW: islandW, islandH: islandH, uploadProgress: 0, hasNotch: state.hasNotch, display: cast.mode)
                let place = CatKittens.placeOf(cast.mode, expanded: true), box = CatIslandLayout.kittenBox(place), u = Double(one.2)
                ProjectKittenLayer(subagents: rows, parentCat: state.bigCatCoat, place: place, unit: one.2, active: state.mode == .expanded && state.view == .overview)
                    .position(x: one.0 + CGFloat((box.x0 + box.x1) / 2 * u), y: one.1 + CGFloat((box.y0 + box.y1) / 2 * u))
                    .frame(width: islandW, height: islandH, alignment: .topLeading)
                    .allowsHitTesting(false)
            }
        } else if compact || overview, !state.kittens.isEmpty {
            let one = botPosition(mode: state.mode, view: state.view, islandW: islandW, islandH: islandH, uploadProgress: 0, hasNotch: state.hasNotch, display: cast.mode)
            let two = secondCatPlace(state: state, islandW: islandW, islandH: islandH)
            let parents = CatIslandLayout.kittenParents(cast.mode, expanded: overview, big: (Double(one.0), Double(one.1), Double(one.2)), second: two.map { (Double($0.cx), Double($0.cy), Double($0.d)) })
            ZStack(alignment: .topLeading) {
                ForEach(parents.filter { !($0.cat == 0 && state.desktopPhase.notchEmpty && !$0.countsBoth) }, id: \.cat) { parent in
                    let spot = parent.cat == 0 ? cast.big : cast.second
                    // The big cat's kittens travel with it: while it is on the desktop its spot in the notch has none (the pair's count then holds cat 2's only).
                    let bigPill = state.desktopPhase.notchEmpty ? nil : cast.big.pill
                    let pills = parent.countsBoth ? [bigPill, cast.second?.pill].compactMap { $0 } : [spot?.pill].compactMap { $0 }
                    if !pills.isEmpty, let spot {
                        layer(pills: pills, cat: spot.cat, place: parent.place, unit: CGFloat(parent.unit), centre: CGPoint(x: parent.x, y: parent.y), colour: parent.countsBoth ? nil : colour(spot.pill))
                    }
                }
            }
            .frame(width: islandW, height: islandH, alignment: .topLeading)
            .allowsHitTesting(false)
        }
    }

    private func colour(_ pill: String?) -> String? { pill.flatMap { id in state.tasks.first { $0.id == id }?.color } }

    private func layer(pills: [String], cat: String, place: String, unit: CGFloat, centre: CGPoint, colour: String?) -> some View {
        let box = CatIslandLayout.kittenBox(place), u = Double(unit)
        return KittenLayerView(state: state, pills: pills, parentCat: cat, place: place, unit: unit, colour: colour)
            .position(x: centre.x + CGFloat((box.x0 + box.x1) / 2 * u), y: centre.y + CGFloat((box.y0 + box.y1) / 2 * u))
    }
}
