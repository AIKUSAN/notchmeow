import SwiftUI
import QuartzCore

// Two cats mode: pair cat 2, beside the big cat, showing the busiest other agent (`CatCast.Result.second`). In the compact island it is a second Ø20 cat in the left
// ear (`CatIslandLayout.compactX`); in the expanded overview it is a Ø46 cat beside the big one, which you can tap to bring its agent into focus. It exists only in
// Two cats mode: in the other two modes `AppState.cast.second` is nil and nothing here is drawn.

/// Where cat 2 sits, in island coordinates, or nil when it is not shown (any view but the overview, the greeting and the upload view draw their own cats).
@MainActor
func secondCatPlace(state: AppState, islandW: CGFloat, islandH: CGFloat) -> (cx: CGFloat, cy: CGFloat, d: CGFloat, compact: Bool)? {
    switch state.mode {
    case .hidden: return nil
    case .compact:
        let resting = IslandRestingLayout(width: islandW, height: islandH)
        return (CGFloat(CatIslandLayout.compactX(.two)[1]), resting.botCenterY, resting.botDiameter, true)
    case .expanded:
        guard CatIslandLayout.secondBesideBig(state.displayMode, overview: state.view == .overview) else { return nil }
        let one = botPosition(mode: .expanded, view: .overview, islandW: islandW, islandH: islandH, uploadProgress: 0)
        let pair = CatIslandLayout.pairExpanded(botX: Double(one.0), cy: Double(one.1))
        return (CGFloat(pair.cat2X), CGFloat(pair.cat2Y), CGFloat(pair.cat2D), false)
    }
}

struct SecondCatPlacement: View {
    @ObservedObject var state: AppState
    let islandW: CGFloat
    let islandH: CGFloat

    var body: some View {
        let cast = state.cast
        if let second = cast.second, let place = secondCatPlace(state: state, islandW: islandW, islandH: islandH) {
            let task = second.pill.flatMap { id in state.tasks.first { $0.id == id } }
            let canvas = place.d / 0.6
            PairCatCanvasView(state: state, task: task, cat: second.cat, compact: place.compact, centre: CGPoint(x: place.cx, y: place.cy), islandW: islandW)
                .frame(width: canvas, height: canvas)
                .overlay { if let id = task?.id, state.sidekickDropPill == id { Circle().stroke(Color.white.opacity(0.85), lineWidth: 1.5).frame(width: place.d * 1.15, height: place.d * 1.15) } }   // a file is over this agent's cat
                .position(x: place.cx, y: place.cy)
                .animation(.spring(response: 0.5, dampingFraction: 0.72), value: place.cx)
                .animation(.spring(response: 0.5, dampingFraction: 0.72), value: place.cy)
                .animation(.spring(response: 0.5, dampingFraction: 0.72), value: canvas)
                .transition(.scale(scale: 0.01, anchor: .center).combined(with: .opacity))
                // Tapping cat 2 in the overview focuses its agent, like tapping a pill. Everywhere else the cat is only drawn.
                .contentShape(Circle().size(width: place.d, height: place.d).offset(x: place.cx - place.d / 2, y: place.cy - place.d / 2))
                .allowsHitTesting(!place.compact && task != nil)
                .onTapGesture {
                    guard let id = task?.id else { return }
                    state.setFocus(id)
                    SoundEngine.shared.play("blip")
                }
        }
    }
}

/// The second cat: a full engine of its own (the big cat's kind), in the coat the cast gives it, in the state of the agent it shows (idle with no badge when there is no
/// other agent), wearing that agent's colour as a collar when it is busy, and asleep with the big cat.
struct PairCatCanvasView: View {
    @ObservedObject var state: AppState
    let task: AgentTask?
    let cat: String
    let compact: Bool
    /// Where the cat is, in island coordinates, and how wide the island is: the cat looks at the pointer from there.
    let centre: CGPoint
    let islandW: CGFloat
    @StateObject private var engine = CatEngine.live()

    var body: some View {
        TimelineView(.animation(minimumInterval: BigCatPacing.minimumInterval, paused: state.mode == .hidden)) { timeline in
            Canvas { context, size in
                _ = timeline.date   // the Canvas redraws on every tick of the timeline
                let dt = CatEngine.frameDelta(now: CACurrentMediaTime(), last: engine.lastTime)
                engine.useCharacter(cat)   // the pair's second coat
                let shown = (task?.state ?? .idle).shown(asleep: state.catAsleep)
                engine.setState(shown)
                engine.collar = CatRules.bigCatCollar(colour: task?.color, state: CatState(rawValue: shown.rawValue) ?? .idle)
                let screen = NSScreen.main ?? NSScreen.screens[0]
                let look = CatGeometry.cursorLook(dx: Double(state.mousePosition.x - (screen.frame.midX - islandW / 2 + centre.x)), dy: Double(state.mousePosition.y - centre.y))
                engine.lookX = look.x
                engine.lookY = look.y
                engine.update(dt: dt)
                let D = Double(size.width) * 0.6, cx = Double(size.width) / 2, cy = Double(size.height) / 2
                var options = CatDrawOptions(badge: task != nil)
                options.badgeSide = compact ? -1 : 1              // in the compact island the right side faces the camera housing
                if compact { options.earCeiling = cy - Double(centre.y) }   // the top of the island is the top of the screen
                options.collar = engine.collarPaint(dpr: Double(context.environment.displayScale))
                // Both cats of Two cats mode are big cats. The canvas is the cat's own (D/0.6, no overhang): its top is y 0, or the strip's top where that is lower (the compact notch).
                options.outfit = CatOutfitDraw.big(engine.cfg.outfit, dpr: Double(context.environment.displayScale), ceiling: max(0, options.earCeiling ?? 0))
                var laid: CatGeometry.Layout?
                context.withCGContext { cg in laid = CatRenderer.draw(cg, engine.look(), cx: cx, cy: cy, D: D, options) }
                if let laid {
                    engine.base = laid.base
                    engine.mouthPoint = laid.mouth
                }
            }
        }
        // A file dropped on this agent's cat: the cat is happy.
        .onReceive(NotificationCenter.default.publisher(for: .sidekickCatEmote)) { note in
            if let id = task?.id, (note.object as? String) == id { engine.triggerEmote(.happy) }
        }
    }
}
