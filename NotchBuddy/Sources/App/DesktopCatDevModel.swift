import Combine
import CoreGraphics
import Foundation
import QuartzCore

#if DEBUG && !APPSTORE

// What the Debug-only cat panel's Desktop section shows and does (sub-project H), with no SwiftUI in it: a mock desktop with the big cat on it, driven by the same pure rules the real
// desktop cat uses (`DesktopCatTrip.step`, the flight's clock, `desktopFps`, `DesktopCatDraw`): fire an alert and watch it fly into the notch, clear it and watch it fly back, pick a size,
// and read the frame rate the rule picks and what a frame costs. tests/DesktopCatDevModelTests.swift drives it; DesktopCatDevPanel.swift draws it. Debug builds only:
// `scripts/check-app-binary.sh` proves a Release build and an App Store build do not contain it. Nothing here touches the app's cats, the store or the island.

@MainActor
final class DesktopCatDevModel: ObservableObject {
    /// In a Debug build and in no other (20 bytes: a shorter string would hide in the code where `strings` cannot see it).
    static let marker = "NM_CAT_DEV_DESKTOP"
    /// The mock desktop, in points (y down), with the notch at the top and the cat's spot below it.
    static let stage = (w: 420.0, h: 260.0)
    static let notch = DesktopSpot(x: 210, y: 34), desk = DesktopSpot(x: 300, y: 170)

    let cfg = CatConfig()
    let now: () -> Double
    private let engine: CatEngine
    private let herd = CatKittenHerd()

    private(set) var phase = DesktopPhase.onDesktop
    private(set) var flight: DesktopCatTrip.Flight?
    private(set) var position = DesktopCatDevModel.desk
    @Published private(set) var size = DesktopSize.medium
    @Published private(set) var kittens = 3
    /// Milliseconds of the last frames' update and draw, smoothed: the readout's "what a frame costs".
    private(set) var frameMs = 0.0
    private var emoteUntil = 0.0
    private var lastMs: Double

    init(now: @escaping () -> Double = { CACurrentMediaTime() * 1000 }, rand: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        self.now = now
        engine = CatEngine(CatPresets.byID("shrimpy"), now: now, rand: rand, cfg: cfg, state: .idle)
        herd.rand = rand
        lastMs = now()
    }

    // MARK: Controls

    func pick(size s: DesktopSize) { size = s }
    /// 0 to 8 kittens beside the cat.
    func pick(kittens n: Int) { kittens = min(max(n, 0), 8) }
    func fireAlert() { send(.alertOn) }
    func clearAlert() { send(.alertOff) }
    func toggle() { send(.toggle) }
    var alertIsOn: Bool { phase == .retracting || phase == .atNotchForAlert }

    /// One event into the machine, and its act carried out on the mock: the same mapping the real controller makes.
    func send(_ e: DesktopEvent) {
        let t = now()
        let r = DesktopCatTrip.step(phase, e)
        phase = r.state
        switch r.act {
        case .retract?:
            engine.emote("surprised"); emoteUntil = t + 1800
            flight = .init(from: position, to: Self.notch, dir: .in, startMs: t + 450)
        case .flyOut?: flight = .start(.out, notch: Self.notch, desktop: Self.desk, at: t); position = Self.notch
        case .flyHome?: flight = .init(from: position, to: Self.notch, dir: .in, startMs: t)
        case .turn?: flight = (flight ?? .init(from: position, to: Self.notch, dir: .in, startMs: t)).turned(at: t)
        case .land?: flight = nil; position = Self.desk
        case .dock?, .goHome?: flight = nil
        default: break
        }
        objectWillChange.send()
    }

    // MARK: A frame

    /// What the rule says now.
    func fps() -> Double {
        DesktopCatTrip.fps(.init(phase: phase, emote: now() < emoteUntil, working: false, cursorDist: nil))
    }

    /// Moves the mock on by the real time since the last frame: the flight, the engine, a flight that is done.
    func advance() {
        let t = now()
        if let f = flight {
            position = f.position(at: t)
            if f.isDone(at: t) { send(.flightDone) }
        }
        engine.useCharacter("shrimpy")
        engine.setState(phase == .retracting || phase == .atNotchForAlert ? CatState.approval : CatState.idle)
        engine.update(dt: CatEngine.frameDelta(now: t / 1000, last: engine.lastTime, maxDt: 0.25))
    }

    /// Draws the mock desktop's cat (nothing when it is in the notch: the real notch would show it) and times the frame.
    func draw(_ cg: CGContext, dpr: Double) {
        let start = CACurrentMediaTime()
        guard phase.drawn else { return }
        let slots = DesktopCatTrip.kittenSlots((0..<kittens).map { CatKittens.Kitten(id: "k\($0)", state: [CatKittens.State.approval, .searching, .working][$0 % 3], born: 0, last: 0) }, side: 1)
        let scene = DesktopCatDraw.Scene(d: size.d, head: (position.x, position.y), slots: slots, parentCat: "shrimpy", colour: "#E07950", dpr: dpr)
        DesktopCatDraw.draw(cg, engine, scene, herd: herd, now: now, cfg: cfg) { $0.update(dt: CatEngine.frameDelta(now: CACurrentMediaTime(), last: $0.lastTime, maxDt: 0.25)) }
        frameMs = frameMs == 0 ? (CACurrentMediaTime() - start) * 1000 : frameMs * 0.9 + (CACurrentMediaTime() - start) * 100
    }

    /// The readout: the phase, the rate the rule picks and what a frame costs, and what that is as a share of a core.
    var readout: String {
        let f = fps()
        let share = DesktopCatPacer.coreShare(msPerFrame: frameMs, fps: f) * 100
        return String(format: "%@ · rule: %.1f fps · a frame %.2f ms · %.2f %% of a core", phase.rawValue, f, frameMs, share)
    }
}

#endif
