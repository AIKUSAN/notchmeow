import SwiftUI
import QuartzCore

#if DEBUG && !APPSTORE

/// The Debug-only cat panel: pick a coat, a size, a motion style and a state, and watch the cat live next to the eleven states and every coat.
/// It is a window opened from the menu bar (AppDelegate), built from the same pieces as Settings (a title, group boxes, system pickers and
/// buttons). Every cat here is a real `CatEngine` drawn by the app's own `CatRenderer`, on its own `CatConfig`: the app's cats are untouched.
/// Compiled in Debug builds only; `scripts/check-app-binary.sh` proves a Release build and an App Store build do not contain it.
struct CatDevView: View {
    @StateObject private var model = CatDevModel()
    /// Where the pointer is, in the content's coordinate space (nil off the content): the cats look at it.
    @State private var pointer: CGPoint?
    static let space = "catpanel"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Cats")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 4)
            Text("Debug builds only. Every cat here is a real engine drawn by the app's own renderer, on its own settings: the app's cats are never touched.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
            // The drawing time of the cats on screen (Windows shows its own in `?dev`): twelve small cats plus the big one stay under 2 ms.
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(CatFrameReadout.shared.latest ?? "Drawing time: measuring…")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
            ScrollView {
                CatDevContent(model: model, pointer: pointer)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                    .coordinateSpace(name: Self.space)
                    .onContinuousHover(coordinateSpace: .named(Self.space)) { phase in
                        switch phase {
                        case .active(let p): pointer = p
                        case .ended: pointer = nil
                        }
                    }
            }
        }
    }
}

/// The panel's sections. `scripts/render-cat-panel.sh` draws this view to a PNG without launching the app (a ScrollView does not render there).
struct CatDevContent: View {
    @ObservedObject var model: CatDevModel
    let pointer: CGPoint?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            chooser
            liveCat
            statesStrip
            greetingBox
            DesktopCatDevView()
            WardrobeDevView()
            ladder
        }
    }

    // MARK: Choosing

    private var chooser: some View {
        GroupBox("Cat") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Coat", selection: Binding(get: { model.coat }, set: { model.pick(coat: $0) })) {
                    ForEach(CatPresets.ids, id: \.self) { Text(CatPresets.byID($0).label).tag($0) }
                }
                Picker("Size", selection: Binding(get: { model.size }, set: { model.pick(size: $0) })) {
                    ForEach(CatDevModel.sizes, id: \.self) { Text("Ø\(Int($0))").tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Motion", selection: Binding(get: { model.motion }, set: { model.pick(motion: $0) })) {
                    Text("Playful").tag("playful")
                    Text("Classic").tag("classic")
                }
                .pickerStyle(.segmented)
                Picker("Personality", selection: Binding(get: { model.personality }, set: { model.pick(personality: $0) })) {
                    ForEach(Personality.presets, id: \.key) { Text($0.label).tag($0.key) }
                }
                Picker("Collar", selection: Binding(get: { model.collar }, set: { model.pick(collar: $0) })) {
                    ForEach(CatDevModel.collars, id: \.id) { Text($0.label).tag($0.id) }
                }
                .pickerStyle(.segmented)
                Picker("Agent colour", selection: Binding(get: { model.agent }, set: { model.pick(agent: $0) })) {
                    ForEach(Array(CatDevModel.agents.enumerated()), id: \.offset) { Text($0.element.name).tag($0.offset) }
                }
                Toggle("Kitten", isOn: Binding(get: { model.kitten }, set: { model.pick(kitten: $0) }))
                Toggle("Fur lines (from a head width of Ø60)", isOn: $model.fur)
                Toggle("State tint on the lower head", isOn: $model.tint)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: The live cat

    private var liveCat: some View {
        GroupBox("Live cat") {
            VStack(alignment: .leading, spacing: 10) {
                CatDevCell(engine: model.stage, D: model.size, width: 360, height: 280, pointer: pointer, tint: model.tint,
                           onFrame: { model.advance() },
                           overlay: { cg, L in
                               // The thrown file, along the contract's flight, in front of the cat (the drop view draws it the same way).
                               guard let k = model.flightProgress, let f = model.flight, let m = L.mouth else { return }
                               let w = CatGreeting.flightAt(from: (x: 360 * 0.86, y: 280 * 0.14), to: (x: m.x, y: m.y), R: L.R, k: k)
                               CatEffects.drawFile(cg, x: w.x, y: w.y, size: w.size, rot: w.rot, ext: f.ext)
                           })
                Text("State")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                ChoiceGrid(items: CatState.allCases.map { ($0.rawValue, $0.rawValue) }, selected: model.state.rawValue) {
                    if let st = CatState(rawValue: $0) { model.pick(state: st) }
                }
                Text("Emote")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                ChoiceGrid(items: CatDevModel.emotes.map { ($0, $0) }, selected: nil) { model.emote($0) }
                HStack(spacing: 10) {
                    Button("Poke") { model.poke() }
                        .buttonStyle(.bordered)
                    Text("or click a cat. Three quick pokes make it dizzy.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Text("File")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                ChoiceGrid(items: CatDevModel.files.map { ($0.name, $0.label) }, selected: nil) { name in
                    if let f = CatDevModel.files.first(where: { $0.name == name }) { model.catchFile(named: f.name, size: f.size) }
                }
                Text("The app's own rule decides at the drop: the cat chews a PDF, and coughs the app and the big file up as a hairball.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    Text("What it just did: " + (model.notes.isEmpty ? "nothing yet" : model.notes.joined(separator: ", ")))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
        }
    }

    // MARK: The eleven states

    private var statesStrip: some View {
        GroupBox("The 11 states") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(Array(model.strip.enumerated()), id: \.offset) { _, e in
                    VStack(spacing: 4) {
                        CatDevCell(engine: e, D: 56, width: 120, height: 130, pointer: pointer, tint: model.tint)
                        Text(e.state.rawValue)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(8)
        }
    }

    // MARK: The greeting

    private var greetingBox: some View {
        GroupBox("Greeting") {
            VStack(alignment: .leading, spacing: 10) {
                Text("The launch greeting: the cat falls in with a landing squash, bounces, slides aside, pops up for a paw wave, slides back and settles. Collapse now cuts it short, the way the pointer leaving the island does.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                CatDevGreeting(engine: model.greeting)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Every coat

    private var ladder: some View {
        GroupBox("Every coat, at every size") {
            ScrollView(.horizontal) {
                CatDevLadder(pointer: pointer, tint: model.tint, collar: model.collar, agent: CatDevModel.agents[model.agent].hex)
            }
            .padding(8)
        }
    }
}

/// The launch greeting, replayable: the same timeline and drawing as the island's (`CatGreeting`, `CatGreetingRenderer`) on the island's black
/// shape. Replay starts it again; Collapse now cuts it short, as the pointer leaving the island does.
private struct CatDevGreeting: View {
    let engine: CatEngine
    @State private var start = CACurrentMediaTime()
    @State private var leave = CatGreeting.GT.leave

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button("Replay") { start = CACurrentMediaTime(); leave = CatGreeting.GT.leave }
                    .buttonStyle(.bordered)
                Button("Collapse now") { leave = min(leave, CACurrentMediaTime() - start) }
                    .buttonStyle(.bordered)
            }
            TimelineView(.animation) { timeline in
                Canvas { context, _ in
                    _ = timeline.date   // the Canvas redraws on every tick of the timeline
                    let t = CACurrentMediaTime() - start
                    engine.update(dt: CatEngine.frameDelta(now: CACurrentMediaTime(), last: engine.lastTime))
                    context.withCGContext { cg in
                        let P = CatGreeting.pose(t, leave: leave)
                        let island = CatDraw.roundRect(320 - P.iw / 2, 0, P.iw, P.ih, 24)
                        cg.fill(island, CatDraw.black(1))
                        cg.saveGState()
                        cg.clip(island)
                        CatGreetingRenderer.draw(cg, t: t, leave: leave, engine: engine, end: CatGreeting.Compact())
                        cg.restoreGState()
                    }
                }
            }
            .frame(width: 640, height: 150)
        }
    }
}

/// A group of buttons of which one is on.
private struct ChoiceGrid: View {
    let items: [(id: String, label: String)]
    let selected: String?
    let pick: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.id) { item in
                Button(item.label) { pick(item.id) }
                    .buttonStyle(.bordered)
                    .tint(item.id == selected ? .accentColor : nil)
            }
        }
    }
}

/// One live cat on a black card, drawn the way the app draws its own: the engine is updated once per frame from one clock
/// (CACurrentMediaTime on both sides of dt), then `CatRenderer` draws it. The cat looks at the pointer; a click pokes it.
private struct CatDevCell: View {
    let engine: CatEngine
    let D: Double
    let width: Double, height: Double
    let pointer: CGPoint?
    var tint = true
    /// Called once per frame before the cat updates (the stage cat's file lands from here).
    var onFrame: (() -> Void)?
    /// Drawn over the cat, in front of it, after its whole draw (the flying file).
    var overlay: ((CGContext, CatGeometry.Layout) -> Void)?

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .named(CatDevView.space)).origin
            let cx = width / 2, cy = height * 0.56
            let gaze = pointer.map { CatGeometry.cursorLook(dx: Double($0.x - origin.x) - cx, dy: Double($0.y - origin.y) - cy) } ?? (x: 0.0, y: 0.0)
            TimelineView(.animation) { timeline in
                Canvas { context, _ in
                    _ = timeline.date   // the Canvas redraws on every tick of the timeline
                    onFrame?()
                    engine.lookX = gaze.x
                    engine.lookY = gaze.y
                    engine.update(dt: CatEngine.frameDelta(now: CACurrentMediaTime(), last: engine.lastTime))
                    CatFrameReadout.shared.measure {
                        context.withCGContext { cg in
                            var options = CatDrawOptions(tint: tint, glow: true)
                            options.fur = engine.cfg.furLines
                            options.collar = engine.collarPaint(dpr: Double(context.environment.displayScale))
                            let L = CatRenderer.draw(cg, engine.look(), cx: cx, cy: cy, D: D, options)
                            engine.base = L.base
                            engine.mouthPoint = L.mouth
                            overlay?(cg, L)
                        }
                    }
                }
            }
        }
        .frame(width: width, height: height)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture { engine.slap() }
    }
}

/// Every coat at Ø12 to Ø66 and as a kitten at Ø16 and Ø40: the ladder of the prototype page and of `render-cats.sh`, still cats that turn
/// to look at the pointer through the face warp (redrawn when the pointer moves, not every frame).
private struct CatDevLadder: View {
    let pointer: CGPoint?
    let tint: Bool
    let collar: String
    let agent: String

    private static let cells: [(d: Double, label: String, kitten: Bool)] = [
        (12, "Ø12 mini", false), (16, "Ø16", false), (20, "Ø20 compact", false), (24, "Ø24", false), (28, "Ø28 full", false),
        (44, "Ø44", false), (66, "Ø66 expanded", false), (16, "kitten Ø16", true), (40, "kitten Ø40", true),
    ]
    private static func slotW(_ d: Double) -> Double { max(62, d * 2.2) }
    private static let rowH = 150.0
    private static let labelW = 130.0
    private static var width: Double { labelW + cells.map { slotW($0.d) }.reduce(0, +) + 12 }

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .named(CatDevView.space)).origin
            Canvas { context, _ in
                let paint = collar == "off" ? nil : CatCollarPaint(style: collar, color: agent, dpr: Double(context.environment.displayScale))
                context.withCGContext { cg in
                    for (ri, id) in CatPresets.ids.enumerated() {
                        let top = Double(ri) * Self.rowH, base = CatPresets.byID(id)
                        CatDraw.text(cg, base.label, x: 12, y: top + Self.rowH / 2 - 6, size: 12, bold: true, color: CatDraw.white(0.9), anchor: .left)
                        CatDraw.text(cg, base.desc ?? id, x: 12, y: top + Self.rowH / 2 + 10, size: 10, bold: false, color: CatDraw.white(0.5), anchor: .left)
                        var x = Self.labelW
                        for c in Self.cells {
                            let w = Self.slotW(c.d), cx = x + w / 2, cy = top + 20 + Self.rowH * 0.42
                            cg.fill(CatDraw.roundRect(x + 4, top + 22, w - 8, Self.rowH - 46, 10), CatDraw.black(1))
                            var pose = CatPose()
                            if let p = pointer {
                                let g = CatGeometry.cursorLook(dx: Double(p.x - origin.x) - cx, dy: Double(p.y - origin.y) - cy)
                                pose.yaw = g.x * 0.62; pose.pitch = g.y * 0.5
                            }
                            var options = CatDrawOptions(tint: tint)
                            options.collar = paint
                            CatRenderer.draw(cg, CatLook(preset: c.kitten ? CatPresets.kitten(of: base) : base, pose: pose), cx: cx, cy: cy, D: c.d, options)
                            CatDraw.text(cg, c.label, x: cx, y: top + Self.rowH - 10, size: 10, bold: false, color: CatDraw.white(0.55))
                            x += w
                        }
                    }
                }
            }
            .frame(width: Self.width, height: Self.rowH * Double(CatPresets.ids.count))
        }
        .frame(width: Self.width, height: Self.rowH * Double(CatPresets.ids.count))
        .background(Color(red: Theme.Brand.pageRGB[0] / 255, green: Theme.Brand.pageRGB[1] / 255, blue: Theme.Brand.pageRGB[2] / 255))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#endif
