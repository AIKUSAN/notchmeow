import Combine
import Foundation
import QuartzCore

#if DEBUG && !APPSTORE

/// What the Debug-only cat panel shows and does, with no SwiftUI in it: which cat, at what size, in which motion style, and the engines
/// it draws (one big live cat and eleven small ones, one per state). The panel (CatDevPanel.swift) draws them; tests/CatDevModelTests.swift
/// drives it. Debug builds only: `scripts/check-app-binary.sh` proves that a Release build and an App Store build do not contain it.
@MainActor
final class CatDevModel: ObservableObject {
    /// `scripts/check-app-binary.sh` looks for this string in a built app: it is in a Debug build and in no other.
    static let marker = "NM_CAT_DEV_PANEL"
    /// The head widths the panel offers: the app's own sizes, from the mini pills (Ø12) to the expanded island (Ø66), and two for a closer look.
    static let sizes: [Double] = [12, 16, 20, 24, 28, 44, 66, 120, 180]
    /// The files the panel can throw at the stage cat: a name and a size, so that the app's own rule (`CatFileRule`) decides what happens, as at a real drop.
    static let files: [(label: String, name: String, size: Int)] = [
        ("A PDF", "notes.pdf", 80_000), ("An app (.exe)", "setup.exe", 5_000_000), ("A 30 MB file", "export.txt", 30 * 1_048_576),
    ]
    /// The emotes of the contract, in the spec's order.
    static let emotes = CatTables.emoteNames

    /// The collar styles the panel offers (the contract's order, Off last), and the agent colours a collar can wear (the pill catalogue's, as the
    /// prototype's collar panel has them).
    static let collars: [(id: String, label: String)] = [("tag", "Band and tag"), ("band", "Band"), ("kerchief", "Neckerchief"), ("off", "Off")]
    static let agents: [(name: String, hex: String)] = [("Claude Code", "#E07950"), ("Gemini CLI", "#8AB4F8"), ("Codex", "#2DD4BF"),
                                                         ("Antigravity", "#E879F9"), ("Cursor", "#C0C4CC"), ("Claude Code pill", "#F5F6F8")]

    /// The panel's own settings. The app's cats (`CatConfig.shared`) are never touched.
    let cfg: CatConfig
    let now: () -> Double
    let rand: () -> Double

    @Published private(set) var coat = "shrimpy"
    @Published private(set) var kitten = false
    @Published private(set) var size = 66.0
    @Published private(set) var motion = "playful"
    @Published private(set) var state = CatState.idle
    @Published private(set) var personality = "balanced"
    @Published var tint = true
    /// The collar every cat in the panel wears, and which agent's colour it is (an index into `agents`). Off is the default, like the app.
    @Published private(set) var collar = "off"
    @Published private(set) var agent = 0
    /// Fur lines on the cats in the panel (its own switch: the app's is Settings').
    @Published var fur = false { didSet { cfg.furLines = fur } }
    /// What the stage cat just did, newest last (the last eight): "emote:love", "blink", "hairball"... They are the engine's own notes.
    /// Not published: the engine writes it while a frame is drawn (SwiftUI does not allow a change to be published from there), so the panel reads it on a timer.
    private(set) var notes: [String] = []
    /// The big live cat, and the eleven small ones, one per state in the contract's order.
    @Published private(set) var stage: CatEngine
    @Published private(set) var strip: [CatEngine] = []
    /// The cat of the launch greeting (it sets its pose directly each frame, so it is an engine of its own).
    @Published private(set) var greeting: CatEngine

    /// `now` is the engines' clock in ms and must be the same clock the views use for `dt` (CACurrentMediaTime): one clock on both sides.
    init(now: @escaping () -> Double = { CACurrentMediaTime() * 1000 }, rand: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        let cfg = CatConfig()
        self.cfg = cfg; self.now = now; self.rand = rand
        stage = CatEngine(CatPresets.byID("shrimpy"), now: now, rand: rand, cfg: cfg)
        greeting = CatEngine(CatPresets.byID("shrimpy"), now: now, rand: rand, cfg: cfg)
        rebuild()
    }

    /// The coat, as a cat or as its kitten.
    var preset: CatPreset {
        let p = CatPresets.byID(coat)
        return kitten ? CatPresets.kitten(of: p) : p
    }

    /// A coat the panel does not know is Shrimpy, like a stored ID the app does not know.
    func pick(coat id: String) { coat = CatPresets.byID(id).name; rebuild() }
    func pick(kitten on: Bool) { kitten = on; rebuild() }
    /// A size the panel does not offer is Ø66, the expanded island's cat.
    func pick(size d: Double) { size = Self.sizes.contains(d) ? d : 66 }
    /// "playful" or "classic"; anything else plays Playful, like a stored style the app does not know.
    func pick(motion style: String) { motion = CatProfiles.named(style) != nil ? style : "playful"; cfg.motion = motion; rebuild() }
    /// The stage cat moves into a state (the eleven small cats each stay in their own).
    func pick(state st: CatState) { state = st; stage.setState(st) }
    /// A preset by name; an unknown name is Balanced, like a stored personality the app does not know. It applies to the chosen coat and follows
    /// it (a kitten wears its parent's). The engines read it as they run, so nothing is rebuilt.
    func pick(personality key: String) { personality = Personality.named(key).preset; cfg.pers = [coat: Personality.named(personality)] }
    /// A collar style; one that is not a style is off, like a stored one. Every engine reads it from the panel's own config on its next frame.
    func pick(collar style: String) { collar = CatRules.collarStyleOf(style); cfg.collar = collar }
    /// An agent colour for the collars; one the panel does not offer is the first.
    func pick(agent i: Int) {
        agent = Self.agents.indices.contains(i) ? i : 0
        for e in [stage, greeting] + strip { e.collar = Self.agents[agent].hex }
    }
    /// A file thrown at the stage cat. Not published: `advance()` changes it while a frame is drawn.
    struct Flight: Equatable { var ext: String; var refused: Bool; var dropAt: Double }
    private(set) var flight: Flight?
    private var pending: (at: Double, ext: String, refused: Bool)?

    /// The file's name and size decide, as at a real drop: the stage cat opens wide, the file drops 0.42 s later and flies in over `CatEngine.flightMs`,
    /// and when it arrives the cat chews it or, for a refused file, gags and coughs it up as a hairball.
    func catchFile(named name: String, size: Int) {
        pending = (now() + 420, CatFileRule.label(for: name), CatFileRule.refused(ext: (name as NSString).pathExtension, size: size))
        flight = nil
        stage.catchOpen(true)
    }

    /// Once per frame, before the stage cat updates: drops the file when its time has come, and lands it.
    func advance() {
        let t = now()
        if let p = pending, t >= p.at {
            pending = nil
            stage.catchDrop()
            flight = Flight(ext: p.ext, refused: p.refused, dropAt: t)
        }
        if let f = flight, t - f.dropAt >= CatEngine.flightMs {
            flight = nil
            if f.refused { stage.catchReject(f.ext) } else { stage.catchArrive() }
        }
    }

    /// How far the flying file is along its flight, 0 to 1; nil when no file is in the air.
    var flightProgress: Double? { flight.map { clamp((now() - $0.dropAt) / CatEngine.flightMs, 0, 1) } }

    /// Plays an emote on the stage cat (an unknown name is ignored by the engine).
    func emote(_ name: String) { stage.emote(name) }
    /// A poke, as a click on a cat does it: three quick ones make it dizzy.
    func poke() { stage.slap() }

    /// New engines for the chosen coat, kitten and motion style: the stage cat in the chosen state, and one small cat per state.
    private func rebuild() {
        let p = preset
        cfg.pers = [coat: Personality.named(personality)]
        pending = nil
        flight = nil
        stage = make(p, state: state)
        stage.onNote = { [weak self] _, event in self?.record(event) }
        strip = CatState.allCases.map { make(p, state: $0) }
        greeting = make(p, state: .idle)
        notes = []
    }

    private func record(_ event: String) {
        notes.append(event)
        if notes.count > 8 { notes.removeFirst(notes.count - 8) }
    }

    private func make(_ p: CatPreset, state: CatState) -> CatEngine {
        let e = CatEngine(p, now: now, rand: rand, cfg: cfg, quiet: false, state: state)
        e.collar = Self.agents[agent].hex
        return e
    }
}

#endif
