import Foundation

// How a cat moves in each state and emote, in the two motion styles, and the tables that go with them (colours, badges, mouths).
// Classic is upstream's timings 1:1; Playful is cat body language on top of the same engine. Port of the "State tables", "Mouth" and
// "Motion profiles" sections of design/prototype/cat-core.js (the tie-breaker); tests/fixtures/cat/motion-cases.json pins them.

enum CatTables {
    /// The state colour, which also tints the lower head and colours the badge.
    static let color: [CatState: String] = Dictionary(uniqueKeysWithValues: CatState.allCases.map { ($0, Theme.State.color[$0.rawValue] ?? "#FFFFFF") })
    static let tint: [CatState: Double] = [
        .idle: 0, .working: 0.72, .thinking: 0.72, .searching: 0.72, .approval: 0.78, .question: 0.75,
        .error: 0.78, .finished: 0.35, .ratelimit: 0.72, .sleeping: 0.32, .dizzy: 0.7,
    ]
    static let glow: [CatState: String] = Dictionary(uniqueKeysWithValues: Theme.State.glow.compactMap { name, hex in CatState(rawValue: name).map { ($0, hex) } })
    static let badge: [CatState: CatBadge] = [
        .working: .dots, .thinking: .dots, .searching: .dots, .approval: .bang, .question: .question, .error: .dot, .finished: .dot, .ratelimit: .dot,
    ]

    /// The six mouth values, in the order the rest mouths list them.
    static let mouthKeys: [PoseKey] = [.mouth, .smile, .tongue, .mround, .mskew, .wavy]
    /// The rest mouth per state: open, smile (-1 frown … 1 smile), tongue, round (D … 'o'), skew, wavy.
    static let mouthRest: [CatState: [Double]] = [
        .idle: [0, 0, 0, 0, 0, 0], .working: [0, 0.05, 0.35, 0, 0, 0], .thinking: [0, -0.15, 0, 0, 0.7, 0], .searching: [0, 0, 0, 0, 0, 0],
        .approval: [0, 0.1, 0, 0.35, 0, 0], .question: [0.13, 0, 0, 1, 0, 0], .error: [0, -0.8, 0, 0, 0, 0], .finished: [0, 1, 0, 0, 0, 0],
        .ratelimit: [0.3, 0, 0.85, 0.2, 0, 0], .sleeping: [0, 0.1, 0, 1, 0, 0], .dizzy: [0, 0, 0.45, 0, 0, 1],
    ]
    /// The emotes the engine knows, in the order the Debug panel offers them. Anything else is ignored.
    static let emoteNames = ["love", "happy", "surprised", "proud", "wink", "yawn", "annoyed", "hello", "zoomies", "hairball"]
    /// Emote mouths, shared by both motion styles: the pose to hold and for how long (ms).
    static let emoteMouth: [String: (pose: [(PoseKey, Double)], ms: Double)] = [
        "love": ([(.smile, 0.8)], 1800), "surprised": ([(.mouth, 0.6), (.mround, 1)], 1000), "proud": ([(.smile, 0.75), (.mskew, 0.45)], 1800),
        "wink": ([(.tongue, 0.8), (.smile, 0.4), (.mskew, 0.3)], 1100), "yawn": ([(.tongue, 0.35), (.mround, 0.15)], 1100),
        "happy": ([(.mouth, 0.5), (.smile, 1)], 1300), "annoyed": ([(.smile, -0.7), (.mskew, -0.6)], 850),
    ]

    /// Per-frame mouth motion on top of the rest shape: hunting chatter, meows, panting, snoring.
    static func mouthFx(_ st: CatState, _ T: Double) -> Double {
        switch st {
        case .searching:
            let ph = T.truncatingRemainder(dividingBy: 2.6)
            return ph < 1.1 ? sin(Double.pi * ph / 1.1) * (0.24 + 0.07 * sin(T * CatMath.tau * 9)) : 0
        case .approval:
            let ph = T.truncatingRemainder(dividingBy: 1.4) / 1.4
            return ph < 0.28 ? 0.5 * sin(Double.pi * ph / 0.28) : 0
        case .ratelimit: return 0.07 * sin(T * CatMath.tau * 2.8)
        case .sleeping: return 0.07 * max(0, sin(T * 1.5))
        default: return 0
        }
    }
}

/// One motion style. Profiles are stateless: they act on the engine they are handed.
@MainActor
protocol MotionProfile {
    var key: String { get }
    var label: String { get }
    /// The eye shape the state rests in.
    func eye(_ st: CatState) -> CatEye
    /// The body language when a state starts.
    func enter(_ c: CatEngine, _ st: CatState, _ prev: CatState)
    /// Fills the pose targets for the state and returns the gaze (yaw, pitch) the head eases toward.
    func targets(_ c: CatEngine, _ st: CatState, _ T: Double, _ tg: inout CatTargets) -> (yaw: Double, pitch: Double)
    /// Per-frame motion applied straight to the pose, after the easing.
    func post(_ c: CatEngine, _ st: CatState, _ T: Double, _ kG: Double)
    /// Idle habits a cat has by itself (the engine skips them when it is quiet).
    func ambient(_ c: CatEngine, _ t: Double)
    /// The squash of a poke: how flat (sy) and how wide (sx).
    var squash: (sy: Double, sx: Double) { get }
    func emote(_ c: CatEngine, _ n: String)
}

enum CatProfiles {
    static func named(_ key: String) -> (any MotionProfile)? {
        switch key {
        case "classic": return ClassicProfile()
        case "playful": return PlayfulProfile()
        default: return nil
        }
    }
}

// MARK: - Classic: upstream timings 1:1

@MainActor
struct ClassicProfile: MotionProfile {
    let key = "classic", label = "Classic"
    /// eye, tilt
    static let rest: [CatState: (eye: CatEye, tilt: Double)] = [
        .idle: (.pill, 0), .working: (.pill, 0), .thinking: (.pill, 0), .searching: (.pill, 0), .approval: (.wide, 0), .question: (.pill, 0.17),
        .error: (.flat, 0), .finished: (.happy, 0), .ratelimit: (.tired, 0), .sleeping: (.closed, 0), .dizzy: (.spiral, 0),
    ]
    let squash = (sy: 0.78, sx: 1.16)

    func eye(_ st: CatState) -> CatEye { Self.rest[st]!.eye }

    func enter(_ c: CatEngine, _ st: CatState, _ prev: CatState) {
        switch st {
        case .idle: if prev != .idle { c.blink() }
        case .approval: c.anim(.oy, [(-0.2, 150, .out), (0, 300, .back)])
        case .error: c.anim(.ox, [(0.08, 50, .out), (-0.08, 70, .inOut), (0.05, 70, .inOut), (0, 90, .out)])
        case .finished:
            c.anim(.roll, [(CatMath.tau, 950, .inOut)]) { $0.s.roll = 0 }
            c.later(500, "st") { $0.emit(.spark, 5) }
        case .ratelimit: c.emit(.sweat, 1)
        case .dizzy: c.anim(.roll, [(2 * CatMath.tau, 1300, .inOut)]) { $0.s.roll = 0 }
        default: c.blink()
        }
    }

    func targets(_ c: CatEngine, _ st: CatState, _ T: Double, _ tg: inout CatTargets) -> (yaw: Double, pitch: Double) {
        tg.tilt = Self.rest[st]!.tilt; tg.earL = 0; tg.earR = 0; tg.earU = 1; tg.earF = 0; tg.pupil = 0.45; tg.oy = 0
        var ty = c.lookX * 0.62, tp = c.lookY * 0.5
        if st == .thinking { ty = ty * 0.35 + 0.55 * 0.55; tp = tp * 0.3 + 0.55 * 0.5 }
        if st == .sleeping { ty = 0; tp = -0.14; tg.sy = 1 + 0.035 * sin(1.8 * T); tg.sx = 1 - 0.035 * 0.57 * sin(1.8 * T) }
        if st == .searching { ty = sin(2.6 * T) * 0.6; tp = -0.06 }
        if st == .dizzy { ty = sin(9 * T) * 0.25 }
        if st == .approval { tg.oy = -abs(sin(5.2 * T)) * 0.07 }
        return (ty, tp)
    }

    func post(_ c: CatEngine, _ st: CatState, _ T: Double, _ kG: Double) {
        if c.tw[.ox] == nil { c.s.ox += (0 - c.s.ox) * kG }
    }

    func ambient(_ c: CatEngine, _ t: Double) {
        if t < c.nextAmb { return }
        if c.state == .sleeping { c.emit(.z, 1) }
        if c.state == .ratelimit && !c.mini && c.rand() < 0.5 { c.emit(.sweat, 1) }
        c.nextAmb = t + 1300
    }

    func emote(_ c: CatEngine, _ n: String) {
        let d = 1800.0
        switch n {
        case "love":
            c.ov(.heart, d); c.anim(.blush, [(1, 300, .out), (1, d - 600, .lin), (0, 300, .inOut)]); c.emit(.heart, 4)
            c.anim(.oy, [(-0.1, 160, .out), (0, 300, .back)])
        case "surprised":
            c.ov(.dot, d); c.anim(.oy, [(-0.3, 140, .out), (0, 380, .back)]); c.anim(.es, [(1.25, 120, .out), (1, 500, .inOut)])
        case "proud":
            c.ov(.star, d); c.emit(.star, 5); c.anim(.tilt, [(-0.14, 220, .out), (-0.14, d - 500, .lin), (0, 280, .inOut)])
            c.anim(.blush, [(0.7, 250, .out), (0.7, d - 550, .lin), (0, 300, .inOut)])
        case "wink":
            c.ov(.wink, d); c.anim(.tilt, [(0.12, 160, .out), (0.12, d - 400, .lin), (0, 240, .inOut)])
        case "yawn":
            c.ov(.tired, d); c.anim(.sy, [(1.12, 500, .inOut), (1, 500, .inOut)]); c.anim(.sx, [(0.94, 500, .inOut), (1, 500, .inOut)])
            c.anim(.mouth, [(0.8, 500, .inOut), (0, 500, .inOut)])
            c.later(700) { $0.ov(.closed, 1100); $0.emit(.z, 2) }
        case "happy":
            c.ov(.happy, d); c.anim(.blush, [(0.6, 200, .out), (0, 600, .inOut)])
        case "annoyed":
            c.ov(.line, 800)
        default: break
        }
    }
}

// MARK: - Playful: cat body language

@MainActor
struct PlayfulProfile: MotionProfile {
    let key = "playful", label = "Playful"
    struct Rest { var eye: CatEye, tilt: Double, earL: Double, earR: Double, earU: Double, earF: Double, pupil: Double, oy: Double }
    static let rest: [CatState: Rest] = [
        .idle: Rest(eye: .pill, tilt: 0, earL: 0, earR: 0, earU: 1, earF: 0, pupil: 0.45, oy: 0),
        .working: Rest(eye: .pill, tilt: 0, earL: -0.08, earR: -0.08, earU: 1.1, earF: 0, pupil: 0.5, oy: 0),
        .thinking: Rest(eye: .pill, tilt: 0.14, earL: 0, earR: 0.38, earU: 1, earF: 0, pupil: 0.55, oy: 0),
        .searching: Rest(eye: .wide, tilt: 0, earL: -0.1, earR: -0.1, earU: 1.15, earF: 0, pupil: 0.92, oy: 0.05),
        .approval: Rest(eye: .wide, tilt: 0, earL: -0.12, earR: -0.12, earU: 1.22, earF: 0, pupil: 0.75, oy: 0),
        .question: Rest(eye: .pill, tilt: 0.24, earL: -0.05, earR: 0.5, earU: 1, earF: 0, pupil: 0.7, oy: 0),
        .error: Rest(eye: .flat, tilt: 0, earL: 0, earR: 0, earU: 1, earF: 1, pupil: 0.12, oy: 0),
        .finished: Rest(eye: .happy, tilt: 0, earL: 0.12, earR: 0.12, earU: 1, earF: 0, pupil: 0.45, oy: 0),
        .ratelimit: Rest(eye: .tired, tilt: 0, earL: 0, earR: 0, earU: 0.9, earF: 0.45, pupil: 0.4, oy: 0),
        .sleeping: Rest(eye: .closed, tilt: 0, earL: 0, earR: 0, earU: 1, earF: 0.25, pupil: 0.45, oy: 0.08),
        .dizzy: Rest(eye: .spiral, tilt: 0, earL: 0, earR: 0, earU: 1, earF: 0, pupil: 0.45, oy: 0),
    ]
    let squash = (sy: 0.86, sx: 1.1)

    func eye(_ st: CatState) -> CatEye { Self.rest[st]!.eye }

    func enter(_ c: CatEngine, _ st: CatState, _ prev: CatState) {
        if prev == .sleeping && st != .sleeping && st != .dizzy { c.later(220, "st") { $0.zoomies() } }
        switch st {
        case .idle: if prev != .idle { c.blink() }
        case .working:
            c.blink(); c.twitch(.earL)
            c.later(140, "st") { $0.twitch(.earR) }
        case .thinking: c.blink()
        case .searching: c.anim(.oy, [(0.12, 160, .out), (0.05, 300, .inOut)])
        case .approval:
            c.anim(.oy, [(0.08, 110, .out), (-0.26, 170, .out), (0, 340, .back)])
            c.anim(.sy, [(0.88, 110, .out), (1.1, 170, .out), (1, 340, .back)])
            c.anim(.sx, [(1.08, 110, .out), (0.94, 170, .out), (1, 340, .back)])
            c.anim(.earU, [(1.4, 140, .out), (1.22, 300, .inOut)])
        case .question:
            c.anim(.tilt, [(0.3, 220, .out), (0.24, 300, .inOut)]); c.blink()
        case .error:
            c.anim(.sx, [(1.14, 80, .out), (1, 450, .inOut)]); c.anim(.sy, [(1.1, 80, .out), (1, 450, .inOut)])
            c.anim(.oy, [(0.07, 80, .out), (0, 420, .inOut)]); c.anim(.earF, [(1, 90, .out)])
            c.anim(.wh, [(0.35, 80, .out), (0, 500, .inOut)])
            c.mpose([(.mouth, 0.75), (.smile, -1), (.mround, 0)], 650, 80, 220)
            c.later(900, "st") { $0.hairball() }
        case .finished:
            if CatRules.zoomiesOnFinish(workedForMs: c.workedFor, thresholdMs: c.cfg.zoomAfter) {
                c.later(150, "st") { $0.zoomies() }
                c.later(2200, "st") { $0.emit(.spark, 4) }
                break
            }
            c.anim(.tilt, [(0.16, 260, .inOut), (-0.16, 420, .inOut), (0.08, 320, .inOut), (0, 300, .inOut)])
            c.anim(.blush, [(0.8, 250, .out), (0.8, 900, .lin), (0, 500, .inOut)])
            c.later(350, "st") { $0.emit(.spark, 5) }
        case .ratelimit: c.nextYawn = c.now() + 300
        default: break
        }
    }

    func targets(_ c: CatEngine, _ st: CatState, _ T: Double, _ tg: inout CatTargets) -> (yaw: Double, pitch: Double) {
        let r = Self.rest[st]!
        tg.tilt = r.tilt; tg.earL = r.earL; tg.earR = r.earR; tg.earU = r.earU; tg.earF = r.earF; tg.pupil = r.pupil; tg.oy = r.oy
        var ty = c.lookX * 0.62, tp = c.lookY * 0.5
        if st == .thinking { ty = ty * 0.35 - 0.55 * 0.55; tp = tp * 0.3 + 0.55 * 0.5 }
        if st == .sleeping { ty = 0; tp = -0.14; tg.sy = 1 + 0.04 * sin(1.2 * T); tg.sx = 1 - 0.04 * 0.57 * sin(1.2 * T) }
        if st == .searching { ty = sin(2.2 * T) * 0.55; tg.earL = -0.1 - sin(2.2 * T) * 0.28; tg.earR = -0.1 + sin(2.2 * T) * 0.28 }
        if st == .dizzy { ty = sin(3.5 * T) * 0.2; tg.tilt = sin(7 * T) * 0.12; tg.earL = sin(9 * T) * 0.45; tg.earR = -sin(9 * T + 1) * 0.45 }
        if st == .approval { tg.oy = -pow(max(0, sin(CatMath.tau * T / 1.4)), 4) * 0.09 }
        if st == .working { tg.oy = -pow(abs(sin(Double.pi * 1.6 * T)), 2) * 0.035 }
        return (ty, tp)
    }

    func post(_ c: CatEngine, _ st: CatState, _ T: Double, _ kG: Double) {
        if c.tw[.ox] == nil {
            if st == .searching { c.s.ox = sin(16 * T) * 0.012 }
            else if st == .dizzy { c.s.ox = cos(7 * T) * 0.07 }
            else { c.s.ox += (0 - c.s.ox) * kG }
        }
        if st == .dizzy && c.tw[.oy] == nil { c.s.oy = sin(7 * T) * 0.05 }
    }

    func ambient(_ c: CatEngine, _ t: Double) {
        let st = c.state
        if st == .idle && t >= c.nextBlep {
            if c.tw[.tongue] == nil && c.tw[.mouth] == nil { if c.rand() < 0.55 { c.blep() } else { c.lick() } }
            c.nextBlep = t + c.u(8000, 15000)
        }
        if [.idle, .working, .thinking, .sleeping, .finished, .question].contains(st) && t >= c.nextTw {
            c.twitch(c.rand() < 0.5 ? .earL : .earR)
            c.nextTw = t + (st == .working ? c.u(1500, 3000) : st == .sleeping ? c.u(4000, 8000) : c.u(3000, 7000)) * c.pm().earFlickEvery
        }
        if st == .idle && t >= c.nextSB {
            c.slowBlink()
            c.nextSB = t + c.u(8000, 14000) * c.pm().slowBlinkEvery
        }
        if st == .ratelimit && t >= c.nextYawn { emote(c, "yawn"); c.nextYawn = t + 4800 }
        if st == .sleeping && t >= c.nextAmb { c.emit(.z, 1); c.nextAmb = t + 1600 }
    }

    func emote(_ c: CatEngine, _ n: String) {
        let d = 1800.0
        switch n {
        case "love":
            c.ov(.closed, d)
            c.anim(.purr, [(1, 200, .out), (1, d - 500, .lin), (0, 300, .inOut)])
            c.anim(.blush, [(1, 300, .out), (1, d - 600, .lin), (0, 300, .inOut)])
            c.anim(.earL, [(0.18, 250, .out), (0.18, d - 500, .lin), (0, 250, .inOut)])
            c.anim(.earR, [(0.18, 250, .out), (0.18, d - 500, .lin), (0, 250, .inOut)])
            c.anim(.tilt, [(c.lookX >= 0 ? 0.12 : -0.12, 400, .inOut), (0, 900, .inOut)])
            c.emit(.heart, 3)
        case "surprised":
            c.ov(.dot, 1100)
            c.anim(.earU, [(1.38, 90, .out), (1, 600, .inOut)])
            c.anim(.sx, [(1.12, 80, .out), (1, 500, .inOut)]); c.anim(.sy, [(1.12, 80, .out), (1, 500, .inOut)])
            c.anim(.oy, [(-0.2, 120, .out), (0, 400, .back)])
            c.anim(.pupil, [(1, 100, .out), (1, 700, .lin), (0.45, 400, .inOut)])
            c.anim(.wh, [(0.4, 80, .out), (0, 500, .inOut)])
        case "proud":
            c.ov(.happy, d)
            c.anim(.lift, [(0.28, 260, .out), (0.28, d - 560, .lin), (0, 300, .inOut)])
            c.anim(.earU, [(1.15, 200, .out), (1.15, d - 500, .lin), (1, 300, .inOut)])
            c.emit(.spark, 4)
            c.anim(.blush, [(0.5, 250, .out), (0.5, d - 550, .lin), (0, 300, .inOut)])
        case "wink":
            c.ov(.wink, 1100); c.twitch(.earR)
            c.anim(.tilt, [(0.1, 180, .out), (0.1, 700, .lin), (0, 240, .inOut)])
        case "yawn":
            c.ov(.closed, 1300)
            c.anim(.mouth, [(1, 450, .out), (1, 500, .lin), (0, 350, .inOut)])
            c.anim(.sy, [(1.12, 450, .inOut), (1, 800, .inOut)]); c.anim(.sx, [(0.94, 450, .inOut), (1, 800, .inOut)])
            c.anim(.earF, [(0.75, 450, .inOut), (c.tg.earF, 800, .inOut)])
        case "happy":
            c.ov(.happy, 1400)
            c.anim(.oy, [(-0.06, 120, .out), (0, 160, .inOut), (-0.06, 120, .out), (0, 200, .back)])
            c.anim(.earU, [(1.12, 150, .out), (1, 600, .inOut)])
            c.anim(.blush, [(0.6, 200, .out), (0, 700, .inOut)])
        case "annoyed":
            c.ov(.line, 900)
            c.anim(.earF, [(1, 60, .out), (1, 700, .lin), (c.tg.earF, 400, .inOut)])
            c.anim(.wh, [(0.4, 60, .out), (0, 400, .inOut)])
        default: break
        }
    }
}
