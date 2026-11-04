import AppKit
import QuartzCore
import SwiftUI

// Settings → Cat, the restyle spec's four tabs: Look (the Main cat, its collar and the desktop switch), Outfits (the Wardrobe, `WardrobeSettingsView.swift`), Personality (the
// personality, the motion and every cat) and Agents' cats (Display first, then the pair or the agents' list). Built from the kit (SettingsCard, SettingRow, SwitchRow, HelpText, WrapRow).
// Everything it shows is `CatSettingsStore.settings`, and every change goes through the store, which cleans it, saves it and hands it to the engines, so a cat in the notch changes while
// you drag a slider. Each cat keeps its own motion override and personality: the rows below the character grid are for the character that is picked.
// `tab` picks one tab; nil draws every group (the render script's whole page, and Settings until the page's tabs are wired in).

struct CatSettingsView: View {
    @ObservedObject var store: CatSettingsStore
    /// True while the Settings window is on screen and the key window (`WindowVisibility` reports it); the previews stop when it is not.
    @State private var windowVisible = true
    /// The offscreen render script has no window to report: it asks for live previews outright.
    private let alwaysActive: Bool
    /// The agent pills on the island now, for "Cats for your agents" (the app's `CatSettingsSection` reads them from `AppState`), and how to name and colour an
    /// agent that is only stored.
    private let agents: [CatAgentList.Agent]
    private let lookup: (String) -> (name: String, color: String)?
    /// Today's date, for the Wardrobe group's Auto tile (the app passes the wardrobe clock's, which a Debug build can override).
    private let wardrobeDay: () -> Wardrobe.Day
    /// The tab to draw; nil draws every group.
    private let tab: SettingsRoute.Tab?
    /// The live projects for "Project cats" (the app's `CatSettingsSection` reads them from `ProjectsModel`): only a folder name and a cat key, never a path.
    private let projects: [ProjectCatList.Live]

    init(store: CatSettingsStore = .shared, alwaysActive: Bool = false, agents: [CatAgentList.Agent] = [], lookup: @escaping (String) -> (name: String, color: String)? = { _ in nil },
         wardrobeDay: @escaping () -> Wardrobe.Day = { Wardrobe.today() }, tab: SettingsRoute.Tab? = nil, projects: [ProjectCatList.Live] = []) {
        self.store = store
        self.alwaysActive = alwaysActive
        self.agents = agents
        self.lookup = lookup
        self.wardrobeDay = wardrobeDay
        self.tab = tab
        self.projects = projects
    }

    private var active: Bool { alwaysActive || windowVisible }
    private var id: String { store.settings.character }
    private var entry: CatSettings.Entry { store.settings.cats[id] ?? CatSettings.Entry() }
    private var label: String { CatPresets.byID(id).label }

    /// A tab shows its groups; nil shows them all.
    private func shows(_ t: SettingsRoute.Tab) -> Bool { tab == nil || tab == t }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if shows(.look) {
                characterGroup
                lookGroup
                desktopGroup
            }
            if shows(.outfits) { WardrobeSettingsGroup(store: store, active: active, day: wardrobeDay) }
            if shows(.personality) {
                personalityGroup
                motionGroup
                allCatsGroup
            }
            if shows(.agentCats) {
                displayGroup
                if store.display.mode == .two { pairGroup }
                if store.display.mode == .perAgent { agentsGroup }
                projectsGroup
            }
        }
        .background(WindowVisibility(visible: $windowVisible))
    }

    // MARK: Display

    private var modeNote: String {
        switch store.display.mode {
        case .one: return "One cat: the Main cat shows every agent, as it always has."
        case .perAgent: return "Every agent has its own cat, so you can tell them apart at a glance. Claude Code is Shrimpy and Codex is Momo; every other agent gets a random coat the first time it appears, and keeps it."
        case .two: return "Your two cats side by side: the first shows the agent you are looking at, the second the busiest other agent. They go to sleep together."
        }
    }

    /// The live picture at its own size, or smaller when the column is narrower (449 pt wide; the 415 window's column is 327 pt). It is scaled from its top left.
    private var displayPreview: some View {
        GeometryReader { geo in
            let full = DisplayPreviewView.island.w * DisplayPreviewView.scale, high = DisplayPreviewView.island.h * DisplayPreviewView.scale
            let s = min(1, geo.size.width / full)
            DisplayPreviewView(display: store.display, main: id, active: active, config: store.config)
                .scaleEffect(s, anchor: .topLeading)
                .frame(width: full * s, height: high * s, alignment: .topLeading)
        }
        .frame(height: DisplayPreviewView.island.h * DisplayPreviewView.scale)
    }

    private var displayGroup: some View {
        SettingsCard("Display") {
            displayPreview
            SettingRow("Show") {
                Picker("", selection: Binding(get: { store.display.mode }, set: { store.setDisplayMode($0) })) {
                    Text("One cat").tag(CatDisplayMode.one)
                    Text("A cat for each agent").tag(CatDisplayMode.perAgent)
                    Text("Two cats").tag(CatDisplayMode.two)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: SettingsLayout.pickerWidth, alignment: .leading)
            }
            HelpText(modeNote)
        }
    }

    // MARK: Desktop (sub-project H)

    /// The Desktop group's note. The App Store build has no dance (`#if !APPSTORE`), so its note leaves the dance out; the GitHub build's text is unchanged.
    private var desktopNote: String {
        #if !APPSTORE
        let moves = "It watches the cursor, dances to music and sleeps"
        #else
        let moves = "It watches the cursor and sleeps"
        #endif
        return "The big cat leaves the notch and lives on your desktop. \(moves), and it flies back to the notch when an approval or a question needs you. You can also drag it out of the notch."
    }

    /// The switch under the Display picker: the big cat out on the desktop, or home in the notch. The cat's own right-click menu picks its size.
    private var desktopGroup: some View {
        SettingsCard("Desktop") {
            SwitchRow("Cat on the desktop", isOn: Binding(get: { store.desktop.on }, set: { store.setDesktopOn($0) }))
            HelpText(desktopNote)
        }
    }

    /// A cat's name in a menu, and the cat it picks.
    private func catPicker(_ selection: Binding<String>) -> some View {
        Picker("", selection: selection) {
            ForEach(CatPresets.ids, id: \.self) { Text(CatPresets.byID($0).label).tag($0) }
        }
        .labelsHidden()
        .frame(width: 160)
    }

    // MARK: The pair (Two cats)

    private var pairGroup: some View {
        SettingsCard("Your two cats") {
            pairRow("Cat 1", slot: 0)
            pairRow("Cat 2", slot: 1)
            HelpText("If both are the same coat, cat 2 becomes the next one.")
        }
    }

    private func pairRow(_ label: String, slot: Int) -> some View {
        let cat = store.display.pair[slot]
        return SettingRow(label) {
            HStack(spacing: 8) {
                CatPreviewView(id: cat, head: 28, active: active, config: store.config)
                    .frame(width: 44, height: 36)
                catPicker(Binding(get: { cat }, set: { store.setPairCat($0, slot: slot) }))
            }
        }
    }

    // MARK: Cats for your agents (A cat for each agent)

    private var agentRows: [CatAgentList.Row] { CatAgentList.rows(agents: agents, display: store.display, main: id, lookup: lookup) }

    private var agentsGroup: some View {
        let rows = agentRows
        return SettingsCard("Cats for your agents") {
            if rows.isEmpty {
                HelpText("No agent has shown up yet. Each one is listed here the first time it sends an event.")
            }
            ForEach(rows, id: \.id) { agentRow($0) }
            WrapRow {
                Button("Reset to defaults") { store.resetAgentCats(for: rows.map(\.id)) }
                    .disabled(rows.isEmpty)
            }
            HelpText("Claude Code is Shrimpy and Codex is Momo; every other agent gets a new random coat.")
        }
    }

    /// One agent: its colour and name (the name wraps), then its cat, the coat picker and the roll.
    private func agentRow(_ row: CatAgentList.Row) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(Color(CatDraw.color(row.color))).frame(width: 8, height: 8).padding(.top, 6)
            VStack(alignment: .leading, spacing: 6) {
                Text(row.name).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    CatPreviewView(id: row.cat, head: 28, active: active, config: store.config, agentColor: row.color)
                        .frame(width: 44, height: 36)
                    catPicker(Binding(get: { row.cat }, set: { store.setAgentCat($0, for: row.id) }))
                    Button("🎲") { store.rerollAgentCat(for: row.id) }
                        .help("Roll a new random coat for \(row.name)")
                        .accessibilityLabel("Roll a new coat for \(row.name)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Project cats (P-mac)

    /// Each live project and each stored one: its name, the cat it shows, the coat picker and Reset for a cat you gave it. The empty sentence shows while no project runs.
    private var projectsGroup: some View {
        let rows = ProjectCatList.rows(live: projects, stored: store.projectCats, main: id)
        return SettingsCard("Project cats") {
            if rows.isEmpty {
                HelpText(ProjectsLayout.emptySettings)
            }
            ForEach(rows, id: \.catKey) { projectRow($0) }
            HelpText("Each project wears the cat you give it, by its folder's name; up to \(ProjectsRules.projectCatsMax) projects keep one. A project without one gets a cat that is not the Main cat.")
        }
    }

    /// One project: its name (the name wraps, never cut), then the cat, the coat picker and Reset, which shows only for a cat you gave it.
    private func projectRow(_ row: ProjectCatList.Row) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.name).fixedSize(horizontal: false, vertical: true)
            WrapRow {
                CatPreviewView(id: row.cat, head: 28, active: active, config: store.config)
                    .frame(width: 44, height: 36)
                catPicker(Binding(get: { row.cat }, set: { store.setProjectCat($0, for: row.catKey) }))
                if row.stored {
                    Button("Reset") { store.resetProjectCat(for: row.catKey) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Main cat

    private var characterGroup: some View {
        SettingsCard("Main cat") {
            HStack(spacing: 14) {
                // A head of Ø60 and more is where fur lines show, so the chosen cat is drawn big (the 16 below are Ø36).
                CatPreviewView(id: id, head: 84, active: active, config: store.config, agentColor: Self.sampleAgent, dressed: true)
                    .frame(width: 130, height: 118)
                VStack(alignment: .leading, spacing: 4) {
                    Text(label).font(.system(size: 13, weight: .semibold))
                    HelpText(CatPresets.byID(id).desc ?? "")
                    HelpText("The cat that lives in your notch and in the small pills. Each one keeps its own motion and personality.")
                    if store.display.mode != .one {
                        HelpText("In this display mode it is the cat of the integration pills (Stripe, Music, Vercel…), and of the notch when no agent is in focus.")
                    }
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 66), spacing: 8)], spacing: 8) {
                ForEach(CatPresets.ids, id: \.self) { tile($0) }
            }
        }
    }

    private func tile(_ cat: String) -> some View {
        let selected = cat == id, preset = CatPresets.byID(cat)
        return Button { store.setCharacter(cat) } label: {
            VStack(spacing: 0) {
                CatPreviewView(id: cat, head: 36, active: active, config: store.config)
                    .frame(width: 60, height: 52)
                Text(preset.label)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .foregroundColor(selected ? .primary : .secondary)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.accentColor.opacity(0.16) : Color(NSColor.controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .help("\(preset.label), \(preset.desc ?? "")")
        .accessibilityLabel(preset.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Motion

    private var motionGroup: some View {
        SettingsCard("Motion") {
            SettingRow("Style") {
                Picker("", selection: Binding(get: { store.settings.motionStyle }, set: { store.setMotionStyle($0) })) {
                    Text("Playful").tag("playful")
                    Text("Classic").tag("classic")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            HelpText("Playful is cat body language. Classic moves 1:1 like the original character.")
            SettingRow("This cat's motion", help: label) {
                Picker("", selection: Binding(get: { entry.motion }, set: { store.setMotionOverride($0, for: id) })) {
                    Text("Follow the style").tag(CatSettings.follow)
                    Text("Playful").tag("playful")
                    Text("Classic").tag("classic")
                }
                .labelsHidden()
                .frame(width: 180)
            }
        }
    }

    // MARK: Personality

    private var personalityGroup: some View {
        SettingsCard("Personality") {
            HStack(spacing: 14) {
                CatPreviewView(id: id, head: 62, active: active, config: store.config, agentColor: Self.sampleAgent, dressed: true)
                    .frame(width: 96, height: 84)
                VStack(alignment: .leading, spacing: 6) {
                    SettingRow("Preset") {
                        Picker("", selection: Binding(get: { entry.personality.preset }, set: { if $0 != "custom" { store.setPreset($0, for: id) } })) {
                            ForEach(Personality.presets, id: \.key) { Text($0.label).tag($0.key) }
                            if entry.personality.preset == "custom" { Text("Custom").tag("custom") }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }
                    HelpText("\(label)'s personality. Moving any slider turns it into Custom.")
                }
            }
            ForEach(Personality.traits, id: \.key) { trait in slider(trait) }
        }
    }

    /// One trait: its name and value on one line, the slider full width, and its two ends under it (a 327 pt column has no room for them in one line).
    private func slider(_ trait: (key: String, label: String, low: String, high: String)) -> some View {
        let value = entry.personality[trait.key] ?? 0.5
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(trait.label)
                Spacer(minLength: 8)
                Text(String(format: "%.2f", value)).font(.system(size: 11).monospacedDigit()).foregroundColor(.secondary)
            }
            Slider(value: Binding(get: { value }, set: { store.setTrait(trait.key, $0, for: id) }), in: 0...1)
            HStack(spacing: 8) {
                Text(trait.low).font(.system(size: 10)).foregroundColor(.secondary)
                Spacer(minLength: 8)
                Text(trait.high).font(.system(size: 10)).foregroundColor(.secondary)
            }
        }
    }

    // MARK: Look

    private static let collarStyles: [(id: String, label: String)] = [("tag", "Band and tag"), ("band", "Band"), ("kerchief", "Neckerchief"), ("off", "Off")]
    /// The colour the previews' collar wears: Claude Code's, one of the agents' colours.
    private static let sampleAgent = "#E07950"

    private var lookGroup: some View {
        SettingsCard("Look") {
            SettingRow("Collar") {
                Picker("", selection: Binding(get: { store.settings.collar }, set: { store.setCollar($0) })) {
                    ForEach(Self.collarStyles, id: \.id) { Text($0.label).tag($0.id) }
                }
                .labelsHidden()
                .frame(width: 180)
            }
            HelpText("The colour of an agent, worn as a collar. Small cats wear their agent's; the big cat wears the agent driving its state, and none when idle.")
            SettingRow("This cat's collar", help: label) {
                Picker("", selection: Binding(get: { entry.collar }, set: { store.setCollarOverride($0, for: id) })) {
                    Text("Follow the collar").tag(CatSettings.follow)
                    ForEach(Self.collarStyles, id: \.id) { Text($0.label).tag($0.id) }
                }
                .labelsHidden()
                .frame(width: 180)
            }
            Divider()
            SwitchRow("Fur lines", isOn: Binding(get: { store.settings.furLines }, set: { store.setFurLines($0) }))
            HelpText("Fine fur strands on the big cat. Off keeps the flat colour.")
        }
    }

    // MARK: Apply to every cat

    private var allCatsGroup: some View {
        SettingsCard("Every cat") {
            Button("Apply to every cat") { store.applyToAll(from: id) }
            HelpText("Copies \(label)'s motion, personality and collar to all 16 cats.")
        }
    }
}

// MARK: - A small live cat

/// A live cat for Settings. It owns one silent engine on the store's `CatConfig` (so it shows that cat's own motion and personality, and a change
/// in Settings shows on its next frame), and it draws only while `active`: the timeline is paused when the Settings window is not on screen.
struct CatPreviewView: View {
    let id: String
    /// The head width in px.
    let head: Double
    let active: Bool
    let config: CatConfig
    /// The agent colour the preview's collar wears (in the style Settings picks); nil: no collar.
    let agentColor: String?
    /// A Main cat's preview is a big cat: it wears the outfit (the owner's answer, 2026-10-14). The rows, the grid and the pairs stay bare.
    let dressed: Bool
    @StateObject private var engine: CatEngine

    init(id: String, head: Double, active: Bool, config: CatConfig, agentColor: String? = nil, dressed: Bool = false) {
        self.id = id; self.head = head; self.active = active; self.config = config; self.agentColor = agentColor; self.dressed = dressed
        _engine = StateObject(wrappedValue: CatEngine(CatPresets.byID(id), now: { CACurrentMediaTime() * 1000 }, cfg: config))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active)) { timeline in
            Canvas { context, size in
                _ = timeline.date   // the Canvas redraws on every tick of the timeline
                engine.useCharacter(id)
                engine.update(dt: CatEngine.frameDelta(now: CACurrentMediaTime(), last: engine.lastTime))
                var options = CatDrawOptions(badge: false)
                options.fur = config.furLines
                engine.collar = agentColor
                options.collar = engine.collarPaint(dpr: Double(context.environment.displayScale))
                // The canvas is just the head and a little more (84 in 130x118): a tall hat is shortened to the room under its top edge (y 0), not cut off by it.
                if dressed { options.outfit = CatOutfitDraw.big(config.outfit, dpr: Double(context.environment.displayScale), ceiling: 0) }
                context.withCGContext { cg in
                    CatRenderer.draw(cg, engine.look(), cx: Double(size.width) / 2, cy: Double(size.height) / 2 + head * 0.08, D: head, options)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Is the window on screen?

/// Reports whether the window this view is in is on screen and the key window: visible, not minimised, not hidden behind other windows, and the one
/// that has the keyboard (the Windows app also stops its previews when Settings is not focused). Settings keeps its window (and its views) after it is
/// closed, so `onAppear` and `onDisappear` cannot tell; the previews pause on this instead.
struct WindowVisibility: NSViewRepresentable {
    @Binding var visible: Bool

    func makeNSView(context: Context) -> NSView {
        let view = TrackerView()
        view.onChange = { visible = $0 }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class TrackerView: NSView {
        var onChange: ((Bool) -> Void)?
        private var tokens: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tokens.forEach { NotificationCenter.default.removeObserver($0) }
            tokens = []
            guard let w = window else { report(false); return }
            let center = NotificationCenter.default
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
                         NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
                tokens.append(center.addObserver(forName: name, object: w, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.report() } })
            }
            // will-close comes while the window still says it is visible: it is hidden by the time anyone asks again, so report it directly.
            tokens.append(center.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.report(false) } })
            report()
        }

        private func report() {
            guard let w = window else { return report(false) }
            report(w.isVisible && !w.isMiniaturized && w.occlusionState.contains(.visible) && w.isKeyWindow)
        }

        /// Reported on the next turn of the run loop: this can be called while SwiftUI is still updating the view.
        private func report(_ on: Bool) { DispatchQueue.main.async { [weak self] in self?.onChange?(on) } }
    }
}
