import SwiftUI

/// Top-level SwiftUI view rendered inside the 720×320 transparent panel.
/// The island is drawn at the top-center; everything else is transparent and click-through.
/// Note: drag-drop is handled at the AppKit level in IslandWindowController (FileDropNSView),
/// not in SwiftUI, to avoid interfering with SwiftUI hit-testing.
struct IslandRootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            IslandContainer(state: state)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Island container

struct IslandContainer: View {
    @ObservedObject var state: AppState
    /// The shelf's count, for its badge in the compact island (sub-project G1).
    @ObservedObject private var shelf = ShelfModel.shared
    /// The Claude Code card's expanded section makes the overview taller (Projects, P-mac): the island's height follows `panelShown`.
    @ObservedObject private var projects = ProjectsModel.shared
    @State private var islandWidth:  CGFloat = IslandConst.notchWidth
    @State private var islandHeight: CGFloat = IslandConst.notchHeight
    @State private var cornerRadius: CGFloat = IslandConst.roundedCorner
    // topRadius > 0 → convex expanded corners; < 0 → concave ear cutouts
    @State private var islandTopRadius: CGFloat = 0

    private let openSpring = Animation.spring(response: 0.5, dampingFraction: 0.72)
    private let closeEase  = Animation.timingCurve(0.45, 0, 0.2, 1, duration: 0.34)
    /// The island's swoosh into the notch and back out (`IslandWing`): a spring with a slight overshoot.
    private let swoosh = Animation.spring(response: IslandWing.springResponse, dampingFraction: IslandWing.springDamping)
    /// The cats', the grid's and the badges' fade as the island shrinks: quick out when the pointer arrives, gentler back (`IslandWing`).
    private var wingAnimation: Animation {
        state.wingYielded ? .easeOut(duration: IslandWing.fadeOut) : .easeInOut(duration: IslandWing.fadeIn)
    }
    /// The width the compact island is drawn at: the notch's own while it has stepped aside (`IslandWing`), its full width otherwise. Its hover zones are always the full island's.
    private var shownWidth: CGFloat { state.mode == .compact && state.wingYielded ? IslandWing.foldedWidth(notchWidth: state.notchWidth) : islandWidth }

    private var chatPromptHeight: CGFloat {
        return ChatSizing.islandHeight(messages: state.chatHistory.count)
    }

    /// Pixels the content must be pushed down to clear the concave ear transparent area.
    /// = 0 in expanded mode (no ears), = earRadius in compact/notch mode.
    private var earOffset: CGFloat { max(0, -islandTopRadius) }

    var body: some View {
        // Canvas active during drag-over (.upload), post-drop animation (.uploading),
        // AND choose overlay (.choose) — canvas handles the full sequence through user action.
        // Engine deactivates when user clicks a canvas choose button or navigates away.
        let uploadActive = state.mode == .expanded
            && UploadSequenceEngine.shared.isActive
            && (state.view == .upload || state.view == .uploading || state.view == .choose)

        let greetingExpanded = state.mode == .expanded && state.view == .greeting
        // After the island has folded the greeting canvas stays up until its last beat (the session cats' glide into the grid) is over.
        let greetingTail = state.greetingTail && state.mode == .compact
        let greetingActive = greetingExpanded || greetingTail
        // The Projects waiting count, read as the island draws (no timer of its own); only the compact island shows it.
        let projectsWaiting = state.mode == .compact ? projects.appView().waiting : 0
        let glowShown = IslandGlow.isShown(enabled: state.hoverGlow, pointerOver: state.islandHovered, islandOnScreen: state.mode != .hidden, dragging: state.isDraggingBot)

        return ZStack(alignment: .topLeading) {
            // Black island shape. The compact island steps aside for the pointer on either wing: it shrinks into the notch on a spring (IslandWing) and back.
            IslandShape(width: shownWidth, height: islandHeight, cornerRadius: cornerRadius, topRadius: islandTopRadius)
                .fill(Color.black)
                .offset(x: (islandWidth - shownWidth) / 2)
                .animation(swoosh, value: state.wingYielded)

            // The hover glow (IslandGlow): along the outline, over the black and under the content, only while the pointer is over the island. Not in the tree otherwise.
            Group {
                if glowShown {
                    // Framed to the island's own size (the shape draws from the origin): the rasterised layer is the island plus the halo's bleed, not the whole 720 x 560 panel.
                    // Open at the top (`openTop`): the island's top is the screen's edge, so the ring runs down the sides and along the bottom only.
                    IslandGlowView(shape: IslandShape(width: shownWidth, height: islandHeight, cornerRadius: cornerRadius, topRadius: islandTopRadius, openTop: true))
                        .frame(width: islandWidth, height: islandHeight, alignment: .topLeading)
                        .offset(x: (islandWidth - shownWidth) / 2)
                        .animation(swoosh, value: state.wingYielded)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: IslandGlow.fade), value: glowShown)

            // Content
            if state.mode == .expanded {
                if greetingExpanded {
                    // The greeting canvas is drawn by the sibling below, so that it survives the island folding.
                    EmptyView()
                } else if uploadActive {
                    ZStack(alignment: .topLeading) {
                        UploadCanvasView(state: state, cat: state.cast.drop)
                            .frame(width: islandWidth, height: islandHeight)
                            .clipShape(IslandShape(width: islandWidth, height: islandHeight,
                                                  cornerRadius: cornerRadius, topRadius: islandTopRadius))
                        // The Shelf half (sub-project G1): a layer over the canvas, only while files are dragged over the notch. The canvas under it, the Ask half, is as it ships.
                        if state.view == .upload, let half = state.dropHalf {
                            ShelfDropLayer(half: half)
                                .frame(width: islandWidth, height: islandHeight, alignment: .topLeading)
                                .clipShape(IslandShape(width: islandWidth, height: islandHeight,
                                                      cornerRadius: cornerRadius, topRadius: islandTopRadius))
                                .transition(.opacity)
                        }
                        // Header overlaid: canvas CARD_Y=42 aligns exactly with header bottom,
                        // matching normal view proportions (8pt top + 34pt header + card + 10pt bottom).
                        IslandHeader(state: state)
                            .frame(width: islandWidth, height: 34)
                            .offset(y: 8)
                    }
                    .transition(.opacity)
                } else {
                    IslandContentView(state: state)
                        .frame(width: islandWidth, height: islandHeight - earOffset)
                        .offset(y: earOffset)
                        .clipShape(IslandShape(width: islandWidth, height: islandHeight,
                                              cornerRadius: cornerRadius, topRadius: islandTopRadius))
                        .transition(.opacity)
                }
            }

            // Greeting canvas: fixed 640-wide, centered by offset so x=320 aligns with island center. It stays up after the island has
            // folded, until the last beat is over, so it is not a child of the expanded block above.
            if greetingActive {
                GreetingCanvasView(state: state)
                    .frame(width: IslandConst.expandedWidth, height: 150)
                    .offset(x: (islandWidth - IslandConst.expandedWidth) / 2)
                    .clipShape(IslandShape(width: islandWidth, height: islandHeight,
                                          cornerRadius: cornerRadius, topRadius: islandTopRadius))
                    .transition(.opacity)
            }

            // Single BotPlacement — always alive in the view tree so spring animations
            // fire from the current position (e.g. choose at 60,101) when canvas deactivates.
            // Hidden during upload canvas or greeting (both draw their own cat).
            BotPlacement(state: state, islandW: islandWidth, islandH: islandHeight)
                // Keep idle animations inside the resting strip. Expanded views
                // retain the panel's full height for particles and hands.
                // The top of the strip is the top of the screen, so this mask cannot give the cat's
                // ears any headroom: BotCanvasView fits them under that edge (CatDrawOptions.earCeiling).
                .mask(alignment: .topLeading) {
                    Rectangle().frame(width: islandWidth,
                                      height: state.mode == .expanded ? 320 : islandHeight)
                }
                .opacity(uploadActive || greetingActive ? 0 : 1)
                .animation(.easeInOut(duration: 0.25), value: uploadActive || greetingActive)
                .opacity(state.wingYielded ? 0 : 1)
                .animation(wingAnimation, value: state.wingYielded)

            // Two cats mode: cat 2, beside the big cat (nothing at all in the other modes).
            SecondCatPlacement(state: state, islandW: islandWidth, islandH: islandHeight)
                .mask(alignment: .topLeading) {
                    Rectangle().frame(width: islandWidth,
                                      height: state.mode == .expanded ? 320 : islandHeight)
                }
                .opacity(uploadActive || greetingActive ? 0 : 1)
                .animation(.easeInOut(duration: 0.25), value: uploadActive || greetingActive)
                .opacity(state.wingYielded ? 0 : 1)
                .animation(wingAnimation, value: state.wingYielded)

            // Subagents, as kittens beside their parent's cat (nothing at all while no agent has one).
            KittenPlacement(state: state, islandW: islandWidth, islandH: islandHeight)
                .mask(alignment: .topLeading) {
                    Rectangle().frame(width: islandWidth,
                                      height: state.mode == .expanded ? 320 : islandHeight)
                }
                .opacity(uploadActive || greetingActive ? 0 : 1)
                .animation(.easeInOut(duration: 0.25), value: uploadActive || greetingActive)
                .opacity(state.wingYielded ? 0 : 1)
                .animation(wingAnimation, value: state.wingYielded)

            CountdownBar(state: state, islandW: islandWidth)

            Group {
                if state.mode == .compact {
                    CompactMiniGrid(state: state)
                        .scaleEffect(IslandRestingLayout(width: islandWidth, height: islandHeight).miniGridScale)
                        .position(x: islandWidth - 40, y: islandHeight / 2)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: state.mode == .compact)
            // While the greeting canvas draws its own session cats the real grid waits, and fades in as the canvas fades out.
            .opacity(greetingTail ? 0 : 1)
            .animation(.easeInOut(duration: 0.25), value: greetingTail)
            // The right wing steps aside for the pointer (IslandWing): the grid fades out in 0.15 s and comes back 1 s after the pointer has left.
            .opacity(state.wingYielded ? 0 : 1)
            .animation(wingAnimation, value: state.wingYielded)

            // Focus awareness (FocusAware): the amber dots on the compact big cat and cat 2, while the island is compact. They fade with the wing and wait for the greeting, like the grid.
            Group {
                if state.mode == .compact {
                    FocusWaitCompactDots(state: state, islandW: islandWidth, islandH: islandHeight)
                }
            }
            .opacity(greetingTail ? 0 : 1)
            .animation(.easeInOut(duration: 0.25), value: greetingTail)
            .opacity(state.wingYielded ? 0 : 1)
            .animation(wingAnimation, value: state.wingYielded)

            // The shelf's badge (sub-project G1): one more cell at the right end of the wing, only while the island is compact and the shelf is not empty. It fades with the wing, like the grid.
            if ShelfBadge.isShown(compact: state.mode == .compact, count: shelf.count, greetingTail: greetingTail) {
                ShelfBadgeView(count: shelf.count, height: islandHeight)
                    .position(ShelfBadge.center(islandWidth: islandWidth, height: islandHeight))
                    .opacity(state.wingYielded ? 0 : 1)
                    .animation(wingAnimation, value: state.wingYielded)
                    .transition(.opacity)
            }

            // The Projects waiting count (P-mac): amber, in the wing's inner end beside the grid, only while the island is compact and something waits. It is a count, never an alert: it
            // fades with the wing and never keeps or wakes the island.
            if ProjectsLayout.badgeShown(compact: state.mode == .compact, waiting: projectsWaiting, greetingTail: greetingTail) {
                ProjectsBadgeView(count: projectsWaiting, height: islandHeight)
                    .position(ProjectsLayout.badgeCenter(islandWidth: islandWidth, height: islandHeight))
                    .opacity(state.wingYielded ? 0 : 1)
                    .animation(wingAnimation, value: state.wingYielded)
                    .transition(.opacity)
            }
        }
        .frame(width: islandWidth, height: islandHeight, alignment: .topLeading)
        .coordinateSpace(name: "nm.island")
        .onChange(of: state.mode) { oldMode, newMode in
            let shrinking = modeOrder(newMode) < modeOrder(oldMode)
            let anim = shrinking ? closeEase : openSpring
            let (w, h) = islandSize(mode: newMode, view: state.view,
                                    progress: state.uploadProgress,
                                    nw: state.notchWidth, nh: state.notchHeight)
            let cr  = newMode == .expanded ? IslandConst.expandedCorner : IslandConst.roundedCorner
            let tr: CGFloat = 0
            withAnimation(anim) {
                islandWidth      = w
                islandHeight     = (newMode == .expanded && state.view == .prompt) ? chatPromptHeight : h
                cornerRadius     = cr
                islandTopRadius  = tr
            }
        }
        .onChange(of: state.view) { _, newView in
            guard state.mode == .expanded else { return }
            // Deactivate engine if user navigates outside the upload flow
            let uploadViews: Set<IslandView> = [.upload, .uploading, .choose]
            if UploadSequenceEngine.shared.isActive && !uploadViews.contains(newView) {
                UploadSequenceEngine.shared.deactivate()
            }
            let (w, h) = islandSize(mode: .expanded, view: newView,
                                    progress: state.uploadProgress,
                                    nw: state.notchWidth, nh: state.notchHeight)
            withAnimation(openSpring) {
                islandWidth  = w
                islandHeight = newView == .prompt ? chatPromptHeight : h
            }
        }
        .onChange(of: state.chatHistory.count) { _, _ in
            guard state.mode == .expanded, state.view == .prompt else { return }
            withAnimation(openSpring) { islandHeight = chatPromptHeight }
        }
        .onChange(of: projects.panelShown) { _, _ in
            guard state.mode == .expanded, state.view == .overview else { return }
            let (w, h) = islandSize(mode: .expanded, view: .overview,
                                    progress: state.uploadProgress,
                                    nw: state.notchWidth, nh: state.notchHeight)
            withAnimation(openSpring) {
                islandWidth  = w
                islandHeight = h
            }
        }
        .onAppear {
            let (w, h) = islandSize(mode: state.mode, view: state.view,
                                    progress: state.uploadProgress,
                                    nw: state.notchWidth, nh: state.notchHeight)
            islandWidth      = w
            islandHeight     = state.view == .prompt ? chatPromptHeight : h
            cornerRadius     = state.mode == .expanded ? IslandConst.expandedCorner : IslandConst.roundedCorner
            islandTopRadius  = 0
        }
    }

    private func modeOrder(_ m: IslandMode) -> Int {
        switch m { case .hidden: return 0; case .compact: return 1; case .expanded: return 2 }
    }
}

// MARK: - Island shape
//
// topRadius > 0  → convex rounded top corners (expanded mode)
// topRadius < 0  → concave ear cutouts, |topRadius| = ear radius (compact/notch mode)
// topRadius = 0  → sharp top corners (transient during animation)

struct IslandShape: Shape {
    var width: CGFloat
    var height: CGFloat
    var cornerRadius: CGFloat   // bottom corners
    var topRadius: CGFloat      // see above
    /// The outline without its top edge, left open (the hover glow's stroke). A fill or a clip never sets it.
    var openTop: Bool = false

    var animatableData: AnimatablePair<AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat>, CGFloat> {
        get { .init(.init(.init(width, height), cornerRadius), topRadius) }
        set {
            width        = newValue.first.first.first
            height       = newValue.first.first.second
            cornerRadius = newValue.first.second
            topRadius    = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let cr = max(0, cornerRadius)
        var p  = Path()

        if topRadius >= 0 {
            // ── Convex rounded top corners (expanded) ──────────────────────────
            let tr = min(topRadius, min(width / 2, height / 2))
            if openTop {
                p.move(to: CGPoint(x: width - tr, y: 0))
            } else {
                p.move(to: CGPoint(x: tr, y: 0))
                p.addLine(to: CGPoint(x: width - tr, y: 0))
            }
            // Top-right convex corner
            p.addArc(center: CGPoint(x: width - tr, y: tr), radius: tr,
                     startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
            // Right edge
            p.addLine(to: CGPoint(x: width, y: height - cr))
            // Bottom-right corner
            p.addArc(center: CGPoint(x: width - cr, y: height - cr), radius: cr,
                     startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            // Bottom edge
            p.addLine(to: CGPoint(x: cr, y: height))
            // Bottom-left corner
            p.addArc(center: CGPoint(x: cr, y: height - cr), radius: cr,
                     startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            // Left edge
            p.addLine(to: CGPoint(x: 0, y: tr))
            // Top-left convex corner
            p.addArc(center: CGPoint(x: tr, y: tr), radius: tr,
                     startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        } else {
            // ── Concave ear cutouts (compact / notch) ─────────────────────────
            let er = -topRadius   // positive ear radius
            if openTop {
                p.move(to: CGPoint(x: width, y: 0))
            } else {
                p.move(to: CGPoint(x: 0, y: 0))
                // Top-left ear
                p.addArc(center: CGPoint(x: 0, y: er), radius: er,
                         startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
                // Top edge
                p.addLine(to: CGPoint(x: width - er, y: er))
                // Top-right ear
                p.addArc(center: CGPoint(x: width, y: er), radius: er,
                         startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            }
            // Right edge
            p.addLine(to: CGPoint(x: width, y: height - cr))
            // Bottom-right corner
            p.addArc(center: CGPoint(x: width - cr, y: height - cr), radius: cr,
                     startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            // Bottom edge
            p.addLine(to: CGPoint(x: cr, y: height))
            // Bottom-left corner
            p.addArc(center: CGPoint(x: cr, y: height - cr), radius: cr,
                     startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            // Left edge back to top-left corner
            p.addLine(to: CGPoint(x: 0, y: 0))
        }

        if !openTop { p.closeSubpath() }
        return p
    }
}

// MARK: - Bot placement helper

struct BotPlacement: View {
    @ObservedObject var state: AppState
    let islandW: CGFloat
    let islandH: CGFloat
    /// A pill click changes the big cat's coat and state (`AppState.bigCatCoat`, `bigCatState`) on the Claude-only card, so this redraws for the model too (Projects, P-mac).
    @ObservedObject private var projects = ProjectsModel.shared

    /// While the cat lives on the desktop (`DesktopPhase.notchEmpty`) its spot in the notch is empty; everything else is as it ships.
    var body: some View {
        if !state.desktopPhase.notchEmpty { catSpot }
    }

    @ViewBuilder private var catSpot: some View {
        let (cx, cy, diameter, opacity) = botPosition(mode: state.mode, view: state.view, islandW: islandW, islandH: islandH, uploadProgress: state.uploadProgress, hasNotch: state.hasNotch, display: state.displayMode)
        let canvasSize = diameter / 0.6
        let overhang: CGFloat = 40
        let isUploading = state.view == .uploading
        let bigState = state.bigCatState   // the glow follows the cat's state (the effective state, or the big card project's on the Claude-only card)

        Group {
            // No glow in uploading mode — the tiny dot doesn't need it
            if state.mode == .expanded && !isUploading {
                Circle()
                    .fill(RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: botGlowColor(bigState), location: 0),
                            .init(color: .clear, location: 0.62)
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: diameter * 1.1
                    ))
                    .frame(width: diameter * 2.2, height: diameter * 2.2)
                    .blur(radius: 6)
                    .opacity(botGlowOpacity(bigState))
                    .position(x: cx, y: cy)
                    .animation(.easeInOut(duration: 0.4), value: bigState)
            }

            // Uploading: no particle overhang (no hearts during upload), positioned directly at cy.
            // The cat is drawn at cy = H/2 (centred in the canvas).
            // With .position(x:y:) placing the frame center at (uploadCx, cy), bot is at cy ✓.
            //
            // Normal: extra 40pt canvas at top for heart particles; position offset up by 20pt;
            // BotCanvasView compensates by drawing the cat at cy = H/2 + particleOverhang/2.
            if isUploading {
                TimelineView(.animation) { tl in
                    let elapsed: Double = {
                        guard let start = state.uploadStartTime else { return 0 }
                        return tl.date.timeIntervalSince(start)
                    }()
                    let t = min(1.0, max(0, elapsed / state.uploadDuration))
                    // cx = 36 + 526*t: bot center at fill right edge (bar left=36, width=526)
                    let uploadCx = 36 + CGFloat(t * (2 - t)) * 526
                    BotCanvasView(state: state, cat: state.bigCatCoat, particleOverhang: 0)
                        .frame(width: canvasSize, height: canvasSize)
                        .opacity(state.isDraggingBot ? 0 : opacity)
                        .position(x: uploadCx, y: cy)
                }
                .transition(.scale(scale: 0.01, anchor: .center).combined(with: .opacity))
            } else {
                BotCanvasView(state: state, cat: state.bigCatCoat, particleOverhang: overhang)
                    .frame(width: canvasSize, height: canvasSize + overhang)
                    .opacity(state.isDraggingBot ? 0 : opacity)
                    .position(x: cx, y: cy - overhang / 2)
                    .animation(.spring(response: 0.5, dampingFraction: 0.72), value: cx)
                    .animation(.spring(response: 0.5, dampingFraction: 0.72), value: cy)
                    .animation(.spring(response: 0.5, dampingFraction: 0.72), value: canvasSize)
                    .transition(.scale(scale: 0.01, anchor: .center).combined(with: .opacity))
            }
        }
        // Branch switch (uploading ↔ normal) animates with a fast spring: uploading dot
        // scales out at bar-end while normal bot scales in at choose position.
        .animation(.spring(response: 0.36, dampingFraction: 0.72), value: isUploading)
        // Slap, drag, and hover are handled by the AppKit NSEvent monitor in
        // IslandWindowController — not SwiftUI gestures — so this is safe.
        .allowsHitTesting(false)
        // While a project's peek is open over the left card the cat (and its glow) steps aside: opacity only, so its engine, state and place are untouched.
        .opacity(state.projectPeeking ? 0 : 1)
        .animation(.easeOut(duration: 0.12), value: state.projectPeeking)
    }

    /// The glow behind the cat: the state's glow colour (`Theme.State.glow`, the colours the contract pins), white for a state with none.
    private func botGlowColor(_ s: BotState) -> Color {
        Theme.State.glow[s.rawValue].map { Color(hex: $0) } ?? Color.white
    }

    private func botGlowOpacity(_ s: BotState) -> Double {
        switch s {
        case .idle, .sleeping: return 0.15
        case .dizzy:           return 0.0
        default:               return 0.65
        }
    }
}

/// Where the big cat sits, in island coordinates: x, y, head width and opacity. `display` is the display mode: in Two cats mode cat 1 moves to make room for cat 2
/// (`CatIslandLayout`), in the compact island and in the overview only; One cat and A cat for each agent are exactly as they have always been.
func botPosition(mode: IslandMode, view: IslandView, islandW: CGFloat, islandH: CGFloat, uploadProgress: Double, hasNotch: Bool = true, display: CatDisplayMode = .one) -> (CGFloat, CGFloat, CGFloat, Double) {
    let resting = IslandRestingLayout(width: islandW, height: islandH)
    switch mode {
    case .hidden:
        return hasNotch ? (46, 16, 6, 0)
            : (islandW / 2, resting.botCenterY, resting.botDiameter, 1)
    case .compact: return (CGFloat(CatIslandLayout.compactX(display)[0]), resting.botCenterY, resting.botDiameter, 1)
    case .expanded:
        let layout = IslandConst.viewLayouts[view]!
        let diameter = layout.botDiameter
        // Uploading: Cat dot rides the leading edge of the progress fill.
        // Bar in island coords: left=36, width=526. cx = 36 + progress*526 (dot center at fill right edge).
        // cy comes from ViewLayout.botY (bar center in island coords).
        if view == .uploading {
            let cx = 36 + CGFloat(uploadProgress) * 526
            return (cx, layout.botY ?? 103, diameter, 1)
        }
        var cx = layout.botX
        let cy: CGFloat
        if let fixedY = layout.botY {
            cy = fixedY
        } else {
            // Center of the fixed 84pt card (VStack top=8, header=34 → content starts at y=42)
            let headerBottom: CGFloat = 42
            let cardH: CGFloat = 84
            // The overview's section under the cards (Projects, P-mac) makes the island taller, but the cards stay where they are: the cat does not move when it opens.
            let h = view == .overview ? min(islandH, layout.height) : islandH
            cy = headerBottom + (h - headerBottom - cardH) / 2 + cardH / 2
        }
        if display == .two && view == .overview {
            cx = CGFloat(CatIslandLayout.pairExpanded(botX: Double(cx), cy: Double(cy)).cat1X)
        }
        return (cx, cy, diameter, 1)
    }
}

// MARK: - Countdown bar

struct CountdownBar: View {
    @ObservedObject var state: AppState
    let islandW: CGFloat
    @State private var barWidth: CGFloat = 0
    @State private var timer: Timer? = nil

    var body: some View {
        GeometryReader { _ in
            Rectangle()
                .fill(Color.white.opacity(0.35))
                .frame(width: barWidth, height: 2)
                .cornerRadius(2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .onAppear { startTimer() }
        .onDisappear { timer?.invalidate() }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            updateBar()
        }
    }

    private func updateBar() {
        guard state.mode == .expanded && !state.isPinned else {
            barWidth = 0
            return
        }
        let autoClose = state.autoCloseInterval
        let window = min(10.0, autoClose * 0.6)
        let elapsed = Date.now.timeIntervalSince(state.lastActivity)
        let remaining = autoClose - elapsed
        if remaining < window {
            barWidth = max(0, CGFloat(remaining / window) * 160)
        } else {
            barWidth = 0
        }
    }
}

// MARK: - Island content (header + views, only in expanded mode)

struct IslandContentView: View {
    @ObservedObject var state: AppState
    /// The Claude Code card's expanded section (Projects, P-mac): while it shows, the overview's frame is as tall as the island lets it be.
    @ObservedObject private var projects = ProjectsModel.shared
    /// True for a moment after the section closes, so the overview keeps its tall frame (its cards stay where they are) while the island's height springs back.
    @State private var panelHeld = false
    /// The pending release of `panelHeld`: a section that closes again before it runs cancels it, so an earlier close never ends a later one's hold early.
    @State private var panelRelease: DispatchWorkItem?

    var body: some View {
        VStack(spacing: 0) {
            IslandHeader(state: state)
                .frame(height: 34)
                .opacity(state.view == .confused ? 0 : 1)
                .animation(.easeInOut(duration: 0.2), value: state.view == .confused)

            ZStack {
                ForEach(IslandView.allCases, id: \.self) { v in
                    let active = state.view == v
                    // Views that fill available height instead of the fixed 98pt content frame:
                    // chat (prompt) is always flexible; mail is flexible only when active so
                    // it doesn't push the ZStack taller when inactive; the shelf and Projects likewise.
                    let tallOverview = v == .overview && (projects.panelShown || panelHeld)
                    let isTall = v == .prompt || (v == .mail && active) || (v == .shelf && active) || (v == .projects && active) || tallOverview
                    let anim: Animation = active
                        ? .spring(response: 0.4, dampingFraction: 0.8).delay(0.16)
                        : .easeIn(duration: 0.16)
                    IslandViewContent(view: v, state: state)
                        .padding(.top, tallOverview ? 5 : 0)   // the cards sit 5 pt under the header, as the 98 pt frame centred in the strip puts them
                        .frame(maxWidth: .infinity)
                        .frame(height: isTall ? nil : 98)
                        .frame(minHeight: (isTall && !active) ? 0 : nil, maxHeight: isTall ? .infinity : nil)
                        .opacity(active ? 1 : 0)
                        .scaleEffect(active ? 1 : 0.97)
                        .allowsHitTesting(active)
                        .animation(anim, value: state.view)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 10)
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
        .foregroundColor(Color(hex: "#F5F6F8"))
        .onChange(of: projects.panelShown) { was, shown in
            guard was, !shown else { return }
            panelHeld = true
            panelRelease?.cancel()
            let release = DispatchWorkItem { panelHeld = false }
            panelRelease = release
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: release)
        }
    }
}

// MARK: - Island header (tabs + icons)

struct IslandHeader: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 0) {
            // Left: tab capsules
            HStack(spacing: 5) {
                TabButton(icon: "house.fill", view: .overview, state: state)
                TabButton(icon: "bubble.left.fill", view: .prompt, state: state, preAction: {
                    #if !APPSTORE
                    if state.promptContext == nil {
                        state.promptContext = WindowContextCapture.captureActive(from: state.lastExternalApp)
                    }
                    #endif
                })
                TabButton(icon: "plus", view: .upload, state: state)
                TabButton(icon: "folder.fill", view: .projects, state: state)
            }
            .padding(.leading, 14)

            Spacer()

            // Right: plan pill (GitHub build, home view only) + action icons
            HStack(spacing: 8) {
                #if !APPSTORE
                if state.view == .overview && state.showPlanInNotch && state.planRelayInstalled {
                    ClaudePlanHeaderPill(state: state)
                }
                #endif
                HStack(spacing: 14) {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            state.view = .settings
                        }
                    }) {
                        Image(systemName: state.view == .settings ? "gearshape.fill" : "gearshape")
                            .font(.system(size: 14))
                            .foregroundColor(state.view == .settings ? Color(hex: "#F5F6F8") : Color(hex: "#8E939C"))
                    }
                    .buttonStyle(.plain)

                    Button(action: { state.soundEnabled.toggle() }) {
                        Image(systemName: state.soundEnabled ? "speaker.wave.2" : "speaker.slash")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "#8E939C"))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.trailing, 16)
        }
        .frame(maxHeight: .infinity)
    }
}

struct TabButton: View {
    let icon: String
    let view: IslandView
    @ObservedObject var state: AppState
    var preAction: (() -> Void)? = nil
    @State private var isHovered = false

    private var isOn: Bool {
        if view == .overview { return state.view == .overview || state.view == .empty }
        return state.view == view
    }

    var body: some View {
        Button(action: {
            preAction?()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                state.view = view
            }
        }) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(isOn ? Color(hex: "#F5F6F8") : (isHovered ? Color(hex: "#B0B5BE") : Color(hex: "#8E939C")))
                .frame(width: 30, height: 22)
                .background(
                    isOn ? Color(hex: "#1D1F23") :
                    isHovered ? Color.white.opacity(0.07) : Color.clear
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Claude Plan header pill (GitHub build only)

#if !APPSTORE
struct ClaudePlanHeaderPill: View {
    @ObservedObject var state: AppState
    @State private var isHovered = false

    private var effectiveColor: String {
        ClaudePlanGauge.color(for: state.claudePlanUsage.flatMap { ClaudePlanGauge.dominantPct($0) })
    }

    private var label: String {
        guard let usage = state.claudePlanUsage,
              let pct = ClaudePlanGauge.dominantPct(usage) else { return "Claude —" }
        return "Claude \(Int(pct.rounded()))%"
    }

    private var isActive: Bool { state.showingPlanDetail || isHovered }

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                state.showingPlanDetail.toggle()
            }
        }) {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color(hex: effectiveColor))
                    .frame(width: 6, height: 6)
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isActive
                                     ? Color(hex: effectiveColor).lighter(by: 0.3)
                                     : Color(hex: "#6B7079"))
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isActive
                          ? Color(hex: effectiveColor).opacity(0.18)
                          : Color(hex: "#0E0F11"))
            )
            .overlay(
                Capsule()
                    .stroke(Color(hex: effectiveColor).opacity(isActive ? 0.55 : 0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { isHovered = h }
        }
    }
}
#endif

// MARK: - Compact mini cat grid (2×2 to the right of the notch)

struct CompactMiniGrid: View {
    @ObservedObject var state: AppState

    /// The pills of the grid with the coat the cast gives each: the tasks other than the focused one (and, in Two cats mode, other than cat 2's), the first four.
    private var others: [(task: AgentTask, cat: String)] {
        state.cast.pills.compactMap { p in state.tasks.first { $0.id == p.pill }.map { ($0, p.cat) } }
    }

    var body: some View {
        let cols = [GridItem(.fixed(12), spacing: 4), GridItem(.fixed(12), spacing: 4)]
        LazyVGrid(columns: cols, spacing: 4) {
            ForEach(others, id: \.task.id) { other in
                MiniBotCanvasView(task: other.task, cat: other.cat)
                    .frame(width: 12 / 0.6, height: 12 / 0.6)
                    .frame(width: 12, height: 12, alignment: .center)
                    .overlay { if state.sidekickDropPill == other.task.id { Circle().stroke(Color.white.opacity(0.85), lineWidth: 1.2).frame(width: 15, height: 15) } }   // a file is over this agent's cat
                    .overlay(alignment: .topTrailing) { if state.focusDot(other.task.id) { FocusWaitDot(size: 5).offset(x: 2, y: -2) } }   // a session waits in its own app (FocusAware)
            }
        }
        .frame(width: 28, height: 28)
    }
}

// MARK: - Color helper

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let val = UInt64(h, radix: 16) ?? 0
        let r = Double((val >> 16) & 0xFF) / 255
        let g = Double((val >> 8)  & 0xFF) / 255
        let b = Double( val        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
