import Combine
import Foundation

// The cat engine: a pose that eases toward the targets of the current state, tweens for the one-off moves, a queue of delayed actions,
// particles, and the file catch, the hairball and the zoomies. One class for both motion styles (a `MotionProfile` holds the style).
// Port of the "Engine" section of design/prototype/cat-core.js (the tie-breaker); tests/fixtures/cat/motion-cases.json and
// sequence-cases.json drive it on a fake clock with a seeded random source and pin every number.
//
// The engine never reads a clock or a random source of its own: `now()` (milliseconds) and `rand()` (0 up to, not including, 1)
// are injected. The order of `rand()` calls is part of the contract: a blink, a flick or a bleep must draw its random numbers at the
// same moment and in the same order as the core, or the random schedule drifts away from the fixtures.

/// The targets the pose eases toward each frame, which the engine's `computeTargets` fills for the current state.
struct CatTargets {
    var yaw = 0.0, pitch = 0.0, tilt = 0.0, sx = 1.0, sy = 1.0, es = 1.0, oy = 0.0
    var earL = 0.0, earR = 0.0, earU = 1.0, earF = 0.0, pupil = 0.45, purr = 0.0, lid = 0.0
    var mouth = 0.0, smile = 0.0, tongue = 0.0, mround = 0.0, mskew = 0.0, wavy = 0.0

    /// A target by pose key; the keys the engine never pulls (roll, open, ox, tint, blush, badgeS, lift, wh, paws) have none, and read as 0.
    subscript(k: PoseKey) -> Double {
        get {
            switch k {
            case .yaw: return yaw
            case .pitch: return pitch
            case .tilt: return tilt
            case .sx: return sx
            case .sy: return sy
            case .es: return es
            case .oy: return oy
            case .earL: return earL
            case .earR: return earR
            case .earU: return earU
            case .earF: return earF
            case .pupil: return pupil
            case .purr: return purr
            case .lid: return lid
            case .mouth: return mouth
            case .smile: return smile
            case .tongue: return tongue
            case .mround: return mround
            case .mskew: return mskew
            case .wavy: return wavy
            default: return 0
            }
        }
        set {
            switch k {
            case .yaw: yaw = newValue
            case .pitch: pitch = newValue
            case .tilt: tilt = newValue
            case .sx: sx = newValue
            case .sy: sy = newValue
            case .es: es = newValue
            case .oy: oy = newValue
            case .earL: earL = newValue
            case .earR: earR = newValue
            case .earU: earU = newValue
            case .earF: earF = newValue
            case .pupil: pupil = newValue
            case .purr: purr = newValue
            case .lid: lid = newValue
            case .mouth: mouth = newValue
            case .smile: smile = newValue
            case .tongue: tongue = newValue
            case .mround: mround = newValue
            case .mskew: mskew = newValue
            case .wavy: wavy = newValue
            default: break
            }
        }
    }
}

/// One key of a tween: the value to reach, how long it takes (ms) and the easing.
typealias CatKey = (target: Double, duration: Double, ease: CatEase)

/// A running tween on one pose property. While it runs, the property is not pulled toward its target.
struct CatTween {
    var from: Double
    var keys: [CatKey]
    var i = 0
    var t0: Double
    var done: (@MainActor (CatEngine) -> Void)?
}

/// The settings every engine reads unless it is given its own: the global motion style, a per-cat motion override (by cat ID),
/// a per-cat personality, and how long a run of work earns zoomies (ms).
@MainActor
final class CatConfig {
    static let shared = CatConfig()
    /// The cat shown in the notch and in the small pills (Settings → Cat → Character; Shrimpy is the default).
    var character = "shrimpy"
    var motion: String
    var override: [String: String]
    var pers: [String: CatPersonality]
    var zoomAfter: Double
    /// Settings → Cat → Fur lines: the optional fur strands on a big cat.
    var furLines = false
    /// Settings → Cat → Collar: the style every cat wears ("tag", "band", "kerchief" or "off", the default), and the cats that have a style of their
    /// own (by cat ID; a cat that follows has no entry).
    var collar = "off"
    var collarOverride: [String: String] = [:]
    /// Settings → Cat → Wardrobe: the outfit every cat in a big-cat role wears now, resolved (one of the 16 IDs, or "none"; never "auto"). The wardrobe's clock keeps it
    /// (`WardrobeClock`); a view reads it on every frame, so a change shows on the next one.
    var outfit = "none"

    /// The collar style a cat wears: its own, else the global one. Anything that is not one of the four styles is "off".
    func collarStyle(for id: String) -> String {
        if let own = collarOverride[id], CatRules.collarStyles.contains(own) { return own }
        return CatRules.collarStyleOf(collar)
    }

    init(motion: String = "playful", override: [String: String] = [:], pers: [String: CatPersonality] = [:], zoomAfter: Double = CatRules.zoomAfterMs) {
        self.motion = motion; self.override = override; self.pers = pers; self.zoomAfter = zoomAfter
    }
}

@MainActor
final class CatEngine: ObservableObject {
    /// The coat. It changes only through `useCharacter`, when the user picks another cat in Settings.
    private(set) var p: CatPreset
    let mini: Bool
    let now: () -> Double
    let rand: () -> Double
    let cfg: CatConfig
    let quiet: Bool
    /// Called with (ms, name) for blinks, flicks, bleps, licks, emotes, zoomies and hairballs. Tests collect them.
    var onNote: ((Int, String) -> Void)?
    /// Called with a sound name ("slap", "annoyed", "greet"); the app plays it. The engine itself is silent.
    var onSound: ((String) -> Void)?
    /// Called on the third quick poke instead of the engine turning dizzy itself (the app's state machine owns dizzy).
    var onDizzy: (() -> Void)?

    var s = CatPose()
    var tg = CatTargets()
    var tw: [PoseKey: CatTween] = [:]
    struct Queued { var at: Double; var tag: String?; var fn: @MainActor (CatEngine) -> Void }
    var q: [Queued] = []
    var parts: [CatParticle] = []
    var balls: [CatBall] = []
    var col = hexRGB(CatTables.color[.idle]!), colT = hexRGB(CatTables.color[.idle]!)
    var gc = [255.0, 255.0, 255.0], ga = 0.12
    var state: CatState = .idle
    var badge: CatBadge?
    var eyeOv: CatEye?
    var eyeUntil = 0.0
    var bt = 0
    var lookX = 0.0, lookY = 0.0
    var slaps: [Double] = []
    var dizzyUntil = 0.0
    var saved: CatState?
    var slotH = 0.0, slotT = 0.0, slotV = 0.0, chew = 0.0, chewStart = 0.0, chewUntil = 0.0
    var catching = false
    var waveStart = 0.0, waveUntil = 0.0, greetTok = 0, hbTok = 0, zoomTok = 0, zoomUntil = 0.0, zv = 0.0, mfx = 0.0
    var busySince: Double?, workedFor = 0.0
    var nextBlink = 0.0, nextTw = 0.0, nextSB = 0.0, nextAmb = 0.0, nextYawn = 0.0, nextBlep = 0.0, nextPers = 0.0
    var blushBase = 0.0
    var miniNext = 0.0
    var miniLook = (x: 0.0, y: 0.0)
    var lastOx: Double?
    /// Where the cat rests and where its mouth is, in px: the renderer hands them back after every draw (the hairball starts at the mouth).
    var base: (x: Double, y: Double, R: Double)?
    var mouthPoint: (x: Double, y: Double)?

    // App-level members that are not in the contract (the fixtures leave them alone).
    /// The eye scale the cat eases to: 1.08 while the pointer hovers its head.
    var tgEs = 1.0
    var isDancing = false
    var dancingLevel = 0.0
    /// Seconds on the engine's clock at the end of the last update, so a view can work out `dt` with `CatEngine.frameDelta`.
    var lastTime: Double
    /// The colour of the agent the cat belongs to, a hex string: small cats wear their agent's, the big cat the colour of the agent driving its state
    /// and none when idle (`CatRules.bigCatCollar`). It is worn as a collar in the style Settings picks (`collarStyle`); nil: nothing to wear.
    var collar: String?

    init(_ p: CatPreset, mini: Bool = false, now: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime * 1000 },
         rand: @escaping () -> Double = { Double.random(in: 0..<1) }, cfg: CatConfig? = nil, quiet: Bool = false, state: CatState = .idle) {
        self.p = p; self.mini = mini; self.now = now; self.rand = rand; self.cfg = cfg ?? CatConfig.shared; self.quiet = quiet
        let t = now()
        lastTime = t / 1000
        nextBlink = t + u(1500, 3500)
        nextTw = t + u(2000, 5000)
        nextSB = t + u(6000, 10000)
        nextAmb = t + 1300
        nextBlep = t + u(5000, 9000)
        nextPers = t + u(3000, 6000)
        setState(state, force: true)
    }

    /// The motion style in force for this cat: its own override, else the global style; an unknown stored value means Playful.
    var motion: String {
        let override = cfg.override[p.base ?? p.name].flatMap { $0.isEmpty ? nil : $0 }
        let m = override ?? cfg.motion
        return CatProfiles.named(m) != nil ? m : "playful"
    }
    var prof: any MotionProfile { CatProfiles.named(motion)! }
    var pers: CatPersonality { cfg.pers[p.base ?? p.name] ?? Personality.named("balanced") }
    /// What this cat's personality changes.
    func pm() -> CatMultipliers { Personality.multipliers(pers) }

    /// Turns this cat into another coat: the one picked in Settings, or the agent's own. Nothing else changes (the state, the pose and the schedule stay), so a
    /// running engine shows the new cat on its next frame. An unknown ID is Shrimpy, like a stored one. A kitten is never turned: its coat is its parent's as a kitten
    /// (`CatPresets.kitten(of:)`), and a kitten's view makes a new engine when the parent's coat changes.
    func useCharacter(_ id: String) {
        guard p.kitten != true else { return }
        let next = CatPresets.byID(id)
        if next.name != p.name { p = next }
    }

    /// The collar style this cat wears (a kitten wears its parent's).
    var collarStyle: String { cfg.collarStyle(for: p.base ?? p.name) }

    /// The collar to hand to the renderer: this cat's style with its agent colour, or nil when the style is off or there is no colour to wear.
    /// `dpr` is the device pixel ratio the readability floors are in.
    func collarPaint(dpr: Double) -> CatCollarPaint? {
        guard let color = collar, collarStyle != "off" else { return nil }
        return CatCollarPaint(style: collarStyle, color: color, dpr: dpr)
    }

    func u(_ a: Double, _ b: Double) -> Double { a + rand() * (b - a) }
    func note(_ ev: String) { onNote?(Int(now().rounded()), ev) }

    // MARK: Tweens and the queue

    func anim(_ k: PoseKey, _ keys: [CatKey], done: (@MainActor (CatEngine) -> Void)? = nil) {
        tw[k] = CatTween(from: s[k], keys: keys, i: 0, t0: now(), done: done)
    }
    func anim(_ k: PoseKey, _ keys: [CatKey], _ done: @escaping @MainActor (CatEngine) -> Void) { anim(k, keys, done: done) }
    func later(_ d: Double, _ tag: String? = nil, _ fn: @escaping @MainActor (CatEngine) -> Void) { q.append(Queued(at: now() + d, tag: tag, fn: fn)) }
    func ov(_ shape: CatEye, _ d: Double) { eyeOv = shape; eyeUntil = now() + d }
    /// Holds a mouth pose for d ms, then eases back to the state's mouth.
    func mpose(_ v: [(PoseKey, Double)], _ d: Double, _ i: Double = 150, _ o: Double = 250) {
        for (k, val) in v { anim(k, [(val, i, .out), (val, max(0, d - i - o), .lin), (tg[k], o, .inOut)]) }
    }

    // MARK: Small moves

    func blep() { note("blep"); anim(.tongue, [(0.7, 150, .out), (0.7, 1300, .lin), (tg.tongue, 220, .inOut)]) }
    func lick() { note("lick"); anim(.mouth, [(0.16, 90, .out), (tg.mouth, 170, .inOut)]); anim(.tongue, [(1, 90, .out), (tg.tongue, 180, .inOut)]) }
    func slowBlink() { note("slowblink"); anim(.lid, [(0.75, 380, .inOut), (0.75, 320, .lin), (0, 480, .inOut)]) }
    func eyeShape() -> CatEye { if let o = eyeOv, now() < eyeUntil { return o }; return prof.eye(state) }
    func blink() { if tw[.open] != nil { return }; note("blink"); anim(.open, [(0.06, 70, .inOut), (1, 130, .out)]) }
    func twitch(_ ear: PoseKey) {
        note("twitch:\(ear.rawValue)")
        let b = tg[ear]
        anim(ear, [(b + 0.5, 60, .out), (b, 280, .back)])
        anim(.wh, [(0.25, 60, .out), (0, 300, .inOut)])
    }

    func emit(_ kind: CatParticleKind, _ n: Int) {
        for i in 0..<n {
            let z = kind == .z
            let x = (rand() - 0.5) * 0.9 + (z ? 0.55 : 0) + s.ox / 1.3
            let y = -0.85 - rand() * 0.2 + s.oy / 1.3
            let vx = (rand() - 0.5) * 0.35 + (z ? 0.18 : 0)
            let vy = -(0.45 + rand() * 0.35)
            let life = 1.3 + rand() * 0.5, size = 0.15 + rand() * 0.08, rot = rand() * 6
            parts.append(CatParticle(kind: kind, x: x, y: y, vx: vx, vy: vy, age: -0.14 * Double(i), life: life, size: size, rot: rot))
        }
    }

    func setBadge(_ b: CatBadge?) {
        bt += 1
        let tok = bt
        anim(.badgeS, [(0, 90, .inOut)])
        later(100) { c in
            if tok != c.bt { return }
            c.badge = b
            if b != nil { c.anim(.badgeS, [(1, 280, .back)]) }
        }
    }

    // MARK: State

    func setState(_ st: CatState, force: Bool = false) {
        if !force && st == state { return }
        let prev = state
        state = st
        q.removeAll { $0.tag == "st" }
        if st != .dizzy { dizzyUntil = 0 }
        colT = hexRGB(CatTables.color[st]!)
        s.tint = CatTables.tint[st]!
        let b = CatTables.badge[st]
        if b != badge || force { setBadge(b) }
        for k in [PoseKey.oy, .ox, .roll, .sx, .sy, .tilt, .earF, .earU, .lid] + CatTables.mouthKeys { tw[k] = nil }
        s.roll = 0
        let wc = CatRules.workClockStep(CatRules.WorkClock(busySince: busySince, workedFor: workedFor), state: st, nowMs: now())
        busySince = wc.busySince; workedFor = wc.workedFor
        if eyeUntil != .infinity { eyeOv = nil }
        prof.enter(self, st, prev)
    }

    func emote(_ n: String) {
        guard CatTables.emoteNames.contains(n) else { return }   // an unknown emote changes nothing and is not noted
        note("emote:\(n)")
        if n == "hello" { return greet() }
        if n == "zoomies" { return zoomies() }
        if n == "hairball" { return hairball() }
        prof.emote(self, n)
        if n == "annoyed" { later(60) { $0.onSound?("annoyed") } }
        if let m = CatTables.emoteMouth[n] { mpose(m.pose, m.ms) }
    }

    /// A poke: a squash, then annoyed (or love, for an affectionate cat); three quick pokes make the cat dizzy.
    func slap() {
        interruptGreet()
        let t = now()
        slaps = slaps.filter { t - $0 < 1700 }
        slaps.append(t)
        let sq = prof.squash
        anim(.sy, [(sq.sy, 70, .out), (1.1, 130, .out), (1, 170, .inOut)])
        anim(.sx, [(sq.sx, 70, .out), (0.95, 130, .out), (1, 170, .inOut)])
        if state == .dizzy { return }
        onSound?("slap")
        if slaps.count >= 3 {
            slaps = []
            if let onDizzy { onDizzy(); return }
            saved = state; setState(CatState.dizzy); dizzyUntil = t + 3300
            return
        }
        let M = pm()
        if M.poke == "love" { return emote("love") }
        emote("annoyed")
        if M.pokeHiss { mpose([(.mouth, 0.6), (.smile, -1), (.mround, 0)], 500, 60, 180) }
    }

    /// Idle habits that come from personality: yawns, zoomies, mews, purrs, hmphs, winks.
    func persAmbient(_ t: Double) {
        let I = pm().idle
        if state != .idle || t < nextPers { return }
        nextPers = t + u(6000, 11000)
        let r = rand()
        if I.yawn && r < 0.5 { return emote("yawn") }
        if I.zoomies && r < 0.35 { return zoomies() }
        if I.mew && r < 0.6 { return mpose([(.mouth, 0.42), (.mround, 0.4), (.smile, 0.2)], 420, 100, 180) }
        if I.purr && r < 0.55 {
            anim(.lid, [(0.75, 380, .inOut), (0.75, 600, .lin), (0, 480, .inOut)])
            return anim(.purr, [(1, 200, .out), (1, 1000, .lin), (0, 300, .inOut)])
        }
        if I.hmph && r < 0.55 { return mpose([(.smile, -0.85), (.mskew, -0.7)], 1000) }
        if I.wink && r < 0.5 { ov(.wink, 550); blep() }
    }

    // MARK: Greeting wave, file catch, hairball, zoomies

    /// Paw wave, upstream's greet timings with paws for hands.
    func greet() {
        let t = now()
        greetTok += 1
        let tok = greetTok
        waveStart = t + 450; waveUntil = t + 1550
        ov(.happy, 2000)
        anim(.oy, [(-0.06, 220, .out), (0, 220, .back)])
        later(250) { c in
            if tok != c.greetTok { return }
            c.anim(.paws, [(1, 280, .out)])
            c.anim(.sy, [(0.95, 100, .out), (1, 260, .back)]); c.anim(.sx, [(1.04, 100, .out), (1, 260, .back)])
            if c.motion == "playful" { c.anim(.earU, [(1.15, 200, .out), (1.15, 900, .lin), (1, 400, .inOut)]) }
            c.onSound?("greet")
        }
        later(450) { if tok == $0.greetTok { $0.mpose([(.mouth, 0.45), (.mround, 0.45), (.smile, 0.35)], 650, 90, 200) } }
        later(550) { if tok == $0.greetTok { $0.blink() } }
        later(1500) { if tok == $0.greetTok { $0.blink() } }
        later(1550) { c in
            if tok != c.greetTok { return }
            c.waveUntil = 0
            c.anim(.paws, [(0, 200, .inOut)])
        }
        later(1750) { if tok == $0.greetTok { $0.ov(.happy, 300) } }
    }

    func interruptGreet() {
        if s.paws <= 0.01 && now() >= waveUntil { return }
        greetTok += 1
        waveUntil = 0; waveStart = 0
        anim(.paws, [(0, 150, .inOut)])
    }

    /// A dropped file arcs into the cat's mouth over this long (ms).
    static let flightMs = 380.0

    /// File catch, step 1: open wide while a file hovers.
    func catchOpen(_ on: Bool) {
        if on == catching { return }
        catching = on
        if on {
            slotT = 0.55; eyeOv = .wide; eyeUntil = .infinity
            anim(.oy, [(-0.05, 160, .out), (-0.03, 200, .inOut)])
        } else {
            slotT = 0
            if eyeUntil == .infinity { eyeOv = nil; eyeUntil = 0 }
        }
    }

    /// Step 2: snap wider on the drop while the file flies in.
    func catchDrop() { catching = true; slotT = 1.05; eyeOv = .wide; eyeUntil = .infinity }

    /// Steps 3 and 4: gulp with a squash, then chew for 0.85 s with happy eyes.
    func catchArrive() {
        catching = false; slotT = 0
        let t = now()
        chewStart = t + 80; chewUntil = t + 930
        ov(.happy, 1250)
        anim(.sy, [(0.8, 80, .out), (1.16, 130, .out), (1, 220, .back)])
        anim(.sx, [(1.24, 80, .out), (0.92, 130, .out), (1, 220, .back)])
        if motion == "playful" {
            anim(.earU, [(1.15, 150, .out), (1, 500, .inOut)])
            anim(.blush, [(0.6, 200, .out), (0, 800, .inOut)])
        }
        later(950, "catch") { $0.lick() }
        later(1000, "catch") { $0.emit(.spark, 3) }
    }

    /// The file has been swallowed: it arrives in the mouth in the time a thrown file takes to fly there.
    func gulp() {
        catchDrop()
        later(CatEngine.flightMs) { $0.catchArrive() }
    }

    /// A file the cat cannot take: it is caught, gagged on and coughed back up as a hairball wrapped around the file.
    func catchReject(_ ext: String) {
        catching = false; slotT = 0; eyeOv = nil; eyeUntil = 0
        q.removeAll { $0.tag == "catch" }   // the chew of an earlier file: its lick and sparks must not fire inside the hairball
        later(CatRules.gagMs) { $0.hairball(ext) }
    }

    /// Hairball: ears back, three heaves, then it comes up (with the file, if it was one).
    func hairball(_ file: String? = nil) {
        note("hairball")
        let pl = motion == "playful"
        hbTok += 1
        let tok = hbTok
        ov(.closed, 1300)
        if pl { anim(.earF, [(0.7, 150, .out), (0.7, 1000, .lin), (tg.earF, 400, .inOut)]) }
        anim(.oy, [(0.06, 140, .out), (0, 180, .inOut), (0.07, 140, .out), (0, 180, .inOut), (0.09, 140, .out), (-0.02, 160, .inOut), (0.11, 170, .out), (0, 320, .back)])
        anim(.sy, [(0.92, 140, .out), (1.04, 180, .inOut), (0.9, 140, .out), (1.05, 180, .inOut), (0.88, 140, .out), (1.06, 160, .inOut), (0.86, 170, .out), (1, 320, .back)])
        anim(.sx, [(1.05, 140, .out), (0.98, 180, .inOut), (1.07, 140, .out), (0.97, 180, .inOut), (1.09, 140, .out), (0.96, 160, .inOut), (1.1, 170, .out), (1, 320, .back)])
        anim(.mouth, [(0.22, 140, .out), (0, 180, .inOut), (0.28, 140, .out), (0, 180, .inOut), (0.34, 140, .out), (0, 160, .inOut), (1.05, 170, .out), (1.05, 160, .lin), (tg.mouth, 260, .inOut)])
        anim(.mround, [(0.3, 140, .out), (0.3, 800, .lin), (0, 170, .out), (0, 420, .lin), (tg.mround, 200, .inOut)])
        anim(.smile, [(-0.7, 140, .out), (-0.7, 970, .lin), (0.5, 330, .inOut), (0.5, 700, .lin), (tg.smile, 300, .inOut)])
        later(1110) { c in if tok == c.hbTok { c.spitBall(file) } }
        later(1450) { c in
            if tok != c.hbTok { return }
            c.ov(.happy, 900)
            if pl { c.anim(.blush, [(0.45, 200, .out), (0, 700, .inOut)]) }
            c.later(320) { $0.lick() }
        }
    }

    func spitBall(_ file: String?) {
        guard let m = mouthPoint, let b0 = base else { return }
        let R = b0.R, dir = rand() < 0.5 ? -1.0 : 1.0, mx = (m.x - b0.x) / R, my = (m.y - b0.y) / R
        let vx = dir * u(0.55, 0.85), vy = u(-0.9, -0.6)
        let seed = Int(rand() * 1e9)
        balls.append(CatBall(x: mx, y: my, vx: vx, vy: vy, rot: 0, age: 0, life: file != nil ? 2.6 : CatRules.hairballMs / 1000, file: file, seed: seed, floor: p.ruff != nil ? 1.34 : 1.12))
        for i in 0..<4 {
            let x = mx / 1.3 + (rand() - 0.5) * 0.15
            let pvx = (rand() - 0.5) * 0.5, pvy = u(-0.35, -0.15)
            let life = 0.9 + rand() * 0.4, size = 0.12 + rand() * 0.05, rot = rand() * 6
            parts.append(CatParticle(kind: .hair, x: x, y: my / 1.3, vx: pvx, vy: pvy, age: -0.05 * Double(i), life: life, size: size, rot: rot))
        }
    }

    /// Zoomies: pupils blown, ears back, side-to-side dashes with skids, then a happy flop.
    func zoomies() {
        note("zoomies")
        let pl = motion == "playful"
        zoomTok += 1
        let tok = zoomTok
        interruptGreet()
        zoomUntil = now() + 1950
        ov(.wide, 1900)
        anim(.pupil, [(1, 120, .out), (1, 1750, .lin), (tg.pupil, 400, .inOut)])
        anim(.earF, [(0.55, 150, .out), (0.55, 1750, .lin), (tg.earF, 400, .inOut)])
        anim(.ox, [(-0.05, 70, .inOut), (0.04, 70, .inOut), (-0.05, 70, .inOut), (0.04, 70, .inOut), (0, 60, .inOut), (0.88, 240, .in), (0.97, 90, .out), (0.84, 110, .inOut),
                   (-0.88, 380, .inOut), (-0.97, 90, .out), (-0.84, 110, .inOut), (0.3, 320, .inOut), (0, 260, .back)])
        mpose([(.mouth, 0.32), (.tongue, 0.9), (.smile, 0.6), (.mround, 0)], 1950, 150, 300)
        later(670) { c in if tok == c.zoomTok { c.dust(1) } }
        later(1250) { c in if tok == c.zoomTok { c.dust(-1) } }
        later(1950) { c in
            if tok != c.zoomTok { return }
            c.ov(.happy, 900)
            c.anim(.sy, [(0.84, 90, .out), (1.06, 150, .out), (1, 220, .back)])
            c.anim(.sx, [(1.14, 90, .out), (0.96, 150, .out), (1, 220, .back)])
            c.emit(.spark, 3)
            if pl { c.anim(.blush, [(0.5, 200, .out), (0, 800, .inOut)]) }
        }
    }

    func dust(_ dir: Double) {
        let y = (p.ruff != nil ? 1.1 : 0.88) / 1.3
        for i in 0..<4 {
            let x = (s.ox + dir * 0.45) / 1.3 + (rand() - 0.5) * 0.2
            let yy = y + (rand() - 0.5) * 0.06
            let vx = -dir * u(0.12, 0.35), vy = -u(0.03, 0.12)
            let life = 0.55 + rand() * 0.2, size = 0.09 + rand() * 0.05
            parts.append(CatParticle(kind: .dust, x: x, y: yy, vx: vx, vy: vy, age: -Double(i) * 0.04, life: life, size: size, rot: 0))
        }
    }

    // MARK: Frame

    /// How open the mouth is right now: the state's mouth plus its motion, or the file-catch spring and chew, whichever is wider.
    func mouthOpen() -> Double { max(s.mouth + mfx, slotH + chew) }

    /// Fills `tg`, the targets the pose eases toward, for the current state: the profile's rest pose, the state's mouth, the personality,
    /// and the file-catch, wave and zoomies overrides. `t` is the clock in ms, `T` the same in seconds. It reads the engine's inputs
    /// (state, lookX/lookY, personality) and never the tweens, so fixtures can call it directly.
    func computeTargets(_ t: Double, _ T: Double) {
        let st = state, pf = prof
        tg.sx = 1; tg.sy = 1; tg.es = tgEs; tg.purr = 0; tg.lid = 0
        let mo = CatTables.mouthRest[st]!
        for (i, k) in CatTables.mouthKeys.enumerated() { tg[k] = mo[i] }
        mfx = CatTables.mouthFx(st, T)
        var (ty, tp) = pf.targets(self, st, T, &tg)
        // Personality: gaze, resting mouth, lids, ears, bounce, pupils, blush and chatter.
        let M = pm()
        ty *= M.gaze; tp *= M.gaze
        tg.smile += M.smile; tg.mskew += M.skew
        if st != .sleeping { tg.lid = max(tg.lid, M.lid) }
        tg.earF = max(tg.earF, M.earBack); tg.oy *= M.hop; tg.pupil = clamp(tg.pupil + M.pupil, 0.1, 1)
        blushBase = st == .sleeping ? 0 : M.blush
        mfx *= M.chatter
        if mini && ![CatState.thinking, .searching, .sleeping, .dizzy].contains(st) {
            if t > miniNext {
                let x = u(-0.88, 0.88), y = u(-0.55, 0.45)
                miniLook = (x, y)
                miniNext = t + u(500, 2000)
            }
            ty = miniLook.x * 0.62; tp = miniLook.y * 0.5
            tg.sy = 1 + sin(2.2 * T) * 0.04; tg.sx = 1 - sin(2.2 * T) * 0.02
        }
        if catching { tg.earU = 1.25; tg.pupil = 0.95; ty *= 0.3; tp = tp * 0.3 + 0.12 }
        if t > waveStart && t < waveUntil {
            let wt = (t - waveStart) / 1000
            tg.tilt = -0.06 + sin(CatMath.tau * 1.2 * wt) * 0.07
        }
        if t < zoomUntil {
            ty = clamp(zv * 0.25, -0.62, 0.62); tp = -0.05
            tg.tilt = clamp(zv * 0.05, -0.2, 0.2)
            tg.sx = 1 + min(0.16, abs(zv) * 0.045); tg.sy = 1 - min(0.09, abs(zv) * 0.025)
            tg.oy = -abs(sin(T * CatMath.tau * 4.5)) * 0.05 * min(1, abs(zv) / 1.5)
        }
        tg.yaw = ty; tg.pitch = tp
    }

    /// One frame. `dt` is seconds; anything outside 0…0.25 (a sleeping laptop, a clock that stepped back, NaN) is held to that range.
    func update(dt dtIn: Double) {
        let dt = dtIn.isFinite ? min(max(dtIn, 0), 0.25) : 0
        let t = now(), T = t / 1000, st = state, pf = prof
        for k in PoseKey.allCases {
            guard var w = tw[k] else { continue }
            var el = t - w.t0
            while w.i < w.keys.count {
                let key = w.keys[w.i], d = max(1, key.duration)
                if el < d { s[k] = lerp(w.from, key.target, key.ease.at(el / d)); break }
                el -= d; w.t0 += d; w.from = key.target; s[k] = key.target; w.i += 1
            }
            if w.i >= w.keys.count { tw[k] = nil; w.done?(self) } else { tw[k] = w }
        }
        let v = (s.ox - (lastOx ?? s.ox)) / max(dt, 1e-3)
        lastOx = s.ox
        zv += (v - zv) * min(1, dt * 18)
        let due = q.filter { $0.at <= t }
        q = q.filter { $0.at > t }
        for x in due { x.fn(self) }
        computeTargets(t, T)
        let M = pm(), ke = M.speed
        let kL = 1 - pow(0.0025, dt * ke), kG = 1 - pow(0.0008, dt * ke), kC = 1 - pow(0.002, dt)
        for k in [PoseKey.yaw, .pitch] where tw[k] == nil { s[k] += (tg[k] - s[k]) * kL }
        for k in [PoseKey.tilt, .sx, .sy, .es, .oy, .earL, .earR, .earU, .earF, .pupil, .purr, .lid] + CatTables.mouthKeys where tw[k] == nil {
            s[k] += (tg[k] - s[k]) * kG
        }
        pf.post(self, st, T, kG)
        let gT = hexRGB(CatTables.glow[st] ?? "#FFFFFF")
        let gaT = st == .dizzy ? 0 : (st == .idle || st == .sleeping ? 0.12 : 0.42)
        for i in 0..<3 {
            col[i] += (colT[i] - col[i]) * kC
            gc[i] += (gT[i] - gc[i]) * kC
        }
        ga += (gaT - ga) * kC
        if !quiet && t >= nextBlink {
            if st != .sleeping && st != .dizzy {
                blink()
                if rand() < 0.22 { later(230) { $0.blink() } }
            }
            nextBlink = t + (2200 + rand() * 3200) * M.blinkEvery
        }
        if eyeOv != nil && t > eyeUntil { eyeOv = nil }
        if !quiet { pf.ambient(self, t); persAmbient(t) }
        if dizzyUntil != 0 && t > dizzyUntil {
            let b = saved ?? .idle
            dizzyUntil = 0
            setState(b, force: true)
            emote("happy")
        }
        for i in parts.indices { parts[i].age += dt }
        parts.removeAll { $0.age >= $0.life }
        for i in balls.indices {
            balls[i].age += dt
            balls[i].vy += 5.5 * dt
            balls[i].x += balls[i].vx * dt
            balls[i].y += balls[i].vy * dt
            if balls[i].y > balls[i].floor {
                balls[i].y = balls[i].floor
                if balls[i].vy > 0.6 { balls[i].vy *= -0.38; balls[i].vx *= 0.7 } else { balls[i].vy = 0; balls[i].vx *= pow(0.2, dt) }
            }
            balls[i].rot += balls[i].vx * dt * 5
        }
        balls.removeAll { $0.age >= $0.life }
        // Mouth spring, ω₀ = 2π/0.25, ζ = 0.6 (upstream's slot spring), stepped at most 1/60 s at a time like the core: a slow frame is
        // several steps, because one step of 0.066 s or more diverges to NaN.
        let om = CatMath.tau / 0.25
        var r = dt
        while r > 0 {
            let h = min(r, 1.0 / 60), acc = om * om * (slotT - slotH) - 2 * 0.6 * om * slotV
            slotV += acc * h
            slotH = max(0, slotH + slotV * h)
            r -= 1.0 / 60
        }
        chew = t >= chewStart && t < chewUntil ? 0.16 * (0.5 - 0.5 * cos(CatMath.tau * 4.2 * (t - chewStart) / 1000)) : 0
        // Apple Music dance level: fades in over 0.3 s and out over 0.5 s.
        let dancingTarget = isDancing ? 1.0 : 0.0
        if dancingLevel < dancingTarget { dancingLevel = min(dancingTarget, dancingLevel + dt / 0.3) }
        else if dancingLevel > dancingTarget { dancingLevel = max(dancingTarget, dancingLevel - dt / 0.5) }
        lastTime = t / 1000
    }

    /// Everything the renderer needs to draw this cat right now. `time` is seconds for the motion inside shapes (defaults to the engine's clock).
    func look(time: Double? = nil) -> CatLook {
        let seconds = time ?? now() / 1000
        // While Apple Music plays the head bobs and the ears bounce on the beat. That rides on what the renderer is given: the engine's own pose, which the
        // fixtures pin, is not touched.
        var l = CatLook(preset: p, pose: CatDance.pose(s, level: dancingLevel, seconds: seconds), eye: eyeShape(), mouthOpen: mouthOpen(), color: col, blushBase: blushBase, time: seconds)
        l.badge = badge
        l.badgeColor = CatTables.color[state]!
        l.glowColor = gc; l.glowAlpha = ga
        l.particles = parts
        l.balls = balls
        l.zoomVelocity = zv
        l.wave = CatWave(now: now(), start: waveStart, until: waveUntil)
        return l
    }

    /// The time between two frames, held to 0…`maxDt` seconds. Both times must come from the engine's own clock (`CatEngine.lastTime`
    /// is on it): mixing two clocks gave the old Mac engine a frame time that was always the maximum.
    static func frameDelta(now: Double, last: Double, maxDt: Double = 0.05) -> Double {
        guard now.isFinite, last.isFinite else { return 0 }
        return max(0, min(maxDt, now - last))
    }

    func setDancing(_ dancing: Bool) { if isDancing != dancing { isDancing = dancing } }
}
