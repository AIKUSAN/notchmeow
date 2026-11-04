import SwiftUI
import QuartzCore

/// The island's big cats (`BotCanvasView`, and `PairCatCanvasView` in Two cats mode) and the launch greeting (`GreetingCanvasView`) redraw at most 60 times a second, whatever the display's rate: on a 120 Hz ProMotion display they used to
/// draw at 120 Hz, which was about half of what the open island cost (measured with scripts/measure-island-cpu.sh; owner's decision of 2026-10-15). A 60 Hz display is unchanged. The engine's
/// time step is the real elapsed time, so the motion's speed does not depend on it. The interval is a hair under 1/60 s (16 ms): a 60 Hz display's frames arrive 16.67 ms apart and must all
/// pass, while a 120 Hz display's arrive 8.33 ms apart and every second one passes.
enum BigCatPacing {
    static let minimumInterval: TimeInterval = 0.016
}

/// SwiftUI wrapper: a TimelineView drives a Canvas that updates the cat engine and draws it with CatRenderer.
/// The main cat; `MiniBotCanvasView` below is the small one for agent pills.
struct BotCanvasView: View {
    @ObservedObject var state: AppState
    /// The coat this cat wears: the cast's (`AppState.cast`), the Main cat in One cat mode. A view never reads the Main cat itself, so a per-agent coat is not
    /// overwritten on the next frame.
    let cat: String
    var particleOverhang: CGFloat = 0

    /// A pill click or a project's own change moves the big card, and with it the state this cat shows (`AppState.bigCatState`), so the cat redraws for the model too.
    @ObservedObject private var projects = ProjectsModel.shared

    // One engine per view instance (main cat)
    @StateObject private var engine = CatEngine.live()

    var body: some View {
        // The state the cat shows: the effective state, or the big card's project's on the Claude-only card (read once per body, not per frame).
        let shownState = state.bigCatState
        return TimelineView(.animation(minimumInterval: BigCatPacing.minimumInterval, paused: state.mode == .hidden)) { timeline in
            Canvas { context, size in
                _ = timeline.date   // the Canvas redraws on every tick of the timeline
                // One clock on both sides of dt: CACurrentMediaTime() here and in the engine (the old code mixed it with the timeline's date).
                let dt = CatEngine.frameDelta(now: CACurrentMediaTime(), last: engine.lastTime)
                engine.useCharacter(cat)   // the cast's coat: Settings → Cat → Main cat, or the agent's own
                let look = lookAt(state: state)
                engine.lookX = look.x
                engine.lookY = look.y
                // The agent colour the collar wears (Settings → Cat → Collar picks the style): the colour of the agent driving the cat's state, and
                // none when it is idle. The Claude plan detail shows the plan gauge's colour.
                #if !APPSTORE
                let agentColour: String? = state.showingPlanDetail
                    ? ClaudePlanGauge.color(for: state.claudePlanUsage.flatMap { ClaudePlanGauge.dominantPct($0) })
                    : state.focusTask?.color
                #else
                let agentColour: String? = state.focusTask?.color
                #endif
                engine.collar = CatRules.bigCatCollar(colour: agentColour, state: CatState(rawValue: shownState.rawValue) ?? .idle)

                // Compute shouldDance per-frame (no observer lag)
                let dancing: Bool = {
                    #if !APPSTORE
                    guard AppState.shared.musicPlaying else { return false }
                    guard AppState.shared.activeIntegrations.contains("integration_music") else { return false }
                    let allowed: Set<BotState> = [.idle, .working, .thinking, .searching, .finished]
                    guard allowed.contains(shownState) else { return false }
                    if state.mode == .compact { return true }
                    return state.mode == .expanded && state.view == .overview && state.focusId == "integration_music"
                    #else
                    return false
                    #endif
                }()
                engine.setDancing(dancing)
                engine.update(dt: dt)

                // The canvas is a square (the bot's diameter over 0.6) plus `particleOverhang` of room above for hearts; the head is as wide as the diameter.
                let D = Double(size.width) * 0.6
                let cx = Double(size.width) / 2, cy = Double(size.height) / 2 + Double(particleOverhang) / 2
                var options = CatDrawOptions()
                options.fur = engine.cfg.furLines                // Settings → Cat → Fur lines
                options.collar = engine.collarPaint(dpr: Double(context.environment.displayScale))   // Settings → Cat → Collar
                options.outfit = CatOutfitDraw.big(engine.cfg.outfit, dpr: Double(context.environment.displayScale))   // Settings → Cat → Wardrobe: the big cat, at every size
                if state.mode == .compact {
                    options.badgeSide = -1                       // never under the camera housing
                    options.earCeiling = cy - Double(restingY(state: state))   // the top of the island is the top of the screen
                } else if CatIslandLayout.secondBesideBig(state.displayMode, overview: state.view == .overview) {
                    options.badgeSide = -1                       // cat 1's badge sits on its left only where cat 2 is drawn beside it
                    options.badgeLeftLimit = cx - CatIslandLayout.pairBadgeReach(cat1X: Double(restingPlace(state: state).botCx))   // and never past the card's left edge
                }
                // A canvas with no overhang (the upload bar's cat, the ghost) is tight: its top is the outfit's ceiling, or the strip's where that is lower. The main cat's has 40 pt (no change).
                if particleOverhang == 0 { options.outfit?.ceiling = max(0, options.earCeiling ?? 0) }
                let L = drawCat(context, engine, cx: cx, cy: cy, D: D, options)
                engine.base = L.base
                engine.mouthPoint = L.mouth
            }
        }
        .onChange(of: shownState) { _, newState in
            engine.setState(newState)
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerEmote)) { notif in
            if let emote = notif.object as? BotEmote {
                engine.triggerEmote(emote)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerSlap)) { _ in
            engine.slap()
        }
        .onReceive(NotificationCenter.default.publisher(for: .botBlink)) { _ in
            engine.blink()
        }
        .onReceive(NotificationCenter.default.publisher(for: .botSetTgEs)) { notif in
            if let v = notif.object as? CGFloat {
                engine.tgEs = Double(v)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .botGulp)) { _ in
            engine.gulp()
        }
        .onAppear {
            engine.onDizzy = { NotificationCenter.default.post(name: .botDizzy, object: nil) }
            engine.setState(shownState, force: true)
        }
    }

    /// Where the island's resting strip puts the cat, in island coordinates.
    private func restingPlace(state: AppState) -> (islandW: CGFloat, botCx: CGFloat, botCy: CGFloat) {
        let (islandW, islandH) = islandSize(mode: state.mode, view: state.view,
                                             progress: state.uploadProgress,
                                             nw: state.notchWidth, nh: state.notchHeight)
        let actualH: CGFloat = (state.mode == .expanded && state.view == .prompt)
            ? ChatSizing.islandHeight(messages: state.chatHistory.count)
            : islandH
        let (botCx, botCy, _, _) = botPosition(mode: state.mode, view: state.view,
                                               islandW: islandW, islandH: actualH,
                                               uploadProgress: state.uploadProgress, display: state.displayMode)
        return (islandW, botCx, botCy)
    }

    private func restingY(state: AppState) -> CGFloat { restingPlace(state: state).botCy }

    /// Where the pointer is, as a look: -1…1 across and up (tanh over 240 px across and 180 px up and down).
    private func lookAt(state: AppState) -> (x: Double, y: Double) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let p = restingPlace(state: state)
        // Island is centered on screen; bot is at botCx within island coords
        let botScreenX = screen.frame.midX - p.islandW / 2 + p.botCx
        // Island top = screen top → bot screen Y = botCy from island top
        return CatGeometry.cursorLook(dx: Double(state.mousePosition.x - botScreenX), dy: Double(state.mousePosition.y - p.botCy))
    }
}

/// Mini cat canvas (for agent pills and the compact grid)
struct MiniBotCanvasView: View {
    let task: AgentTask
    /// The coat this cat wears: the cast's, for this pill.
    let cat: String
    var isDancing: Bool = false
    @StateObject private var engine: CatEngine

    init(task: AgentTask, cat: String, isDancing: Bool = false) {
        self.task = task
        self.cat = cat
        self.isDancing = isDancing
        _engine = StateObject(wrappedValue: {
            let e = CatEngine.live(CatPresets.byID(cat), mini: true)
            e.collar = task.color
            return e
        }())
    }

    var body: some View {
        // Small cats redraw 30 times a second: at Ø12 to Ø24 the difference cannot be seen, and a dozen of them are most of the frame time.
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            Canvas { context, size in
                _ = timeline.date   // the Canvas redraws on every tick of the timeline
                let dt = CatEngine.frameDelta(now: CACurrentMediaTime(), last: engine.lastTime)
                engine.useCharacter(cat)   // the cast's coat for this pill
                engine.setState(task.state.shown(asleep: AppState.shared.catAsleep))   // an idle pill's cat sleeps with the big one
                engine.setDancing(isDancing)
                engine.update(dt: dt)
                let D = Double(size.width) * 0.6
                var options = CatDrawOptions(badge: false)
                options.collar = engine.collarPaint(dpr: Double(context.environment.displayScale))   // the pill's agent colour, in Settings → Cat → Collar's style
                let L = drawCat(context, engine, cx: Double(size.width) / 2, cy: Double(size.height) / 2, D: D, options)
                engine.base = L.base
                engine.mouthPoint = L.mouth
            }
        }
        .onChange(of: task.state) { _, newState in
            engine.setState(newState.shown(asleep: AppState.shared.catAsleep))
        }
        .onAppear {
            engine.setState(task.state.shown(asleep: AppState.shared.catAsleep), force: true)
        }
        // A file dropped on this agent's cat: the cat is happy.
        .onReceive(NotificationCenter.default.publisher(for: .sidekickCatEmote)) { note in
            if (note.object as? String) == task.id { engine.triggerEmote(.happy) }
        }
    }
}

/// Draws a cat into a SwiftUI canvas context (with the Apple Music dance applied) and returns its layout.
@MainActor
private func drawCat(_ context: GraphicsContext, _ engine: CatEngine, cx: Double, cy: Double, D: Double, _ options: CatDrawOptions) -> CatGeometry.Layout {
    // The layout is set straight inside `withCGContext` (no closure around it): Xcode 26's Release build refuses a captured `var` sent through a second closure.
    var laid: CatGeometry.Layout?
    #if DEBUG
    CatFrameReadout.shared.measure {   // twelve small cats plus the big one stay under 2 ms: see CatFrameMeter
        context.withCGContext { cg in laid = drawCatInto(cg, engine, cx: cx, cy: cy, D: D, options) }
    }
    #else
    context.withCGContext { cg in laid = drawCatInto(cg, engine, cx: cx, cy: cy, D: D, options) }
    #endif
    return laid!
}

/// The drawing itself: the Apple Music dance, then the cat.
@MainActor
private func drawCatInto(_ cg: CGContext, _ engine: CatEngine, cx: Double, cy: Double, D: Double, _ options: CatDrawOptions) -> CatGeometry.Layout {
    if engine.dancingLevel > 0.001 {
        let R = D / 2
        CatEffects.applyDance(cg, level: engine.dancingLevel, seconds: CACurrentMediaTime(), pivotX: cx, pivotY: cy + D * 0.45, size: R)
    }
    return CatRenderer.draw(cg, engine.look(), cx: cx, cy: cy, D: D, options)
}

// MARK: - CGColor from hex string

func cgColorFromHex(_ hex: String) -> CGColor? {
    let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard let val = UInt64(h, radix: 16) else { return nil }
    let r = CGFloat((val >> 16) & 0xFF) / 255
    let g = CGFloat((val >> 8)  & 0xFF) / 255
    let b = CGFloat( val        & 0xFF) / 255
    return CGColor(red: r, green: g, blue: b, alpha: 1)
}

extension CGColor {
    static func from(_ hex: String) -> CGColor {
        cgColorFromHex(hex) ?? CGColor(gray: 0.5, alpha: 1)
    }
}
