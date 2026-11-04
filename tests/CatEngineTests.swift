import Foundation

@main
enum CatEngineTests {
    static let fps = 60.0
    static func frameMs(_ f: Int) -> Double { Double(f) * 1000 / fps }
    static func num(_ x: Any?) -> Double { (x as! NSNumber).doubleValue }
    static let sampleFrames = [0, 5, 10, 16, 24, 34, 46, 60, 78, 102, 132, 180]

    /// An engine on a fake clock and a seeded rand, the way the fixtures were made (the reference is `makeEngine` in scripts/gen-cat-fixtures.mjs).
    /// R is exactly 1, so a hairball lands in units of R.
    @MainActor static func makeEngine(_ preset: CatPreset, profile: String = "playful", pers: [String: CatPersonality] = [:], seed: UInt32 = 1,
                                      quiet: Bool = true, state: CatState = .idle, zoomAfter: Double = CatRules.zoomAfterMs,
                                      note: ((Int, String) -> Void)? = nil) -> (e: CatEngine, clock: FakeClock, step: (Int) -> Void) {
        let clock = FakeClock(), rng = CatRNG(seed: seed)
        let cfg = CatConfig(motion: profile, override: [:], pers: pers, zoomAfter: zoomAfter)
        let e = CatEngine(preset, now: { clock.t }, rand: { rng.next() }, cfg: cfg, quiet: quiet, state: state)
        e.onNote = note
        let L = CatGeometry.layout(preset, e.s, cx: 0, cy: 0, D: 2 * preset.rx)
        e.base = L.base; e.mouthPoint = L.mouth
        return (e, clock, { f in clock.t = frameMs(f); e.update(dt: 1 / fps) })
    }

    @MainActor static func columns(_ want: [String: Any]) -> [String] { want["columns"] as! [String] }

    /// The engine's numbers for one frame, named like the fixture's columns.
    @MainActor static func row(_ e: CatEngine) -> [String: Any] {
        var r: [String: Any] = ["mouthOpen": e.mouthOpen(), "slotH": e.slotH, "chew": e.chew, "parts": e.parts.count, "balls": e.balls.count,
                                "ballX": e.balls.first?.x ?? 0, "ballY": e.balls.first?.y ?? 0]
        for k in PoseKey.allCases { r[k.rawValue] = e.s[k] }
        return r
    }
    static func wantRow(_ cols: [String], _ v: [Any]) -> [String: Any] { Dictionary(uniqueKeysWithValues: zip(cols, v)) }

    /// Runs from frame 0, calling `start` there, and returns one row per sample frame (the reference is `sample` in the generator).
    @MainActor static func sample(_ preset: CatPreset, profile: String, frames: [Int] = sampleFrames, start: (CatEngine) -> Void) -> [Int: (eye: String, v: [String: Any])] {
        let (e, _, step) = makeEngine(preset, profile: profile)
        start(e)
        var out: [Int: (String, [String: Any])] = [:]
        for f in 0...frames.last! {
            if f > 0 { step(f) }
            if frames.contains(f) { out[f] = (e.eyeShape().rawValue, row(e)) }
        }
        return out
    }

    /// Compares the sampled rows of one case with the fixture's rows for it.
    @MainActor static func compareRows(_ label: String, _ got: [Int: (eye: String, v: [String: Any])], _ rows: [[String: Any]], _ cols: [String]) {
        var diffs: [String] = []
        for r in rows {
            let f = Int(num(r["f"]))
            guard let g = got[f] else { diffs.append("frame \(f) missing"); continue }
            // `tMs` is derived data, exactly f * 1000 / 60, and `f` is the authority: it only has to agree within 1e-8 (the contract's port notes).
            if let t = r["tMs"] as? NSNumber, abs(t.doubleValue - frameMs(f)) > 1e-8 { diffs.append("frame \(f) tMs \(t) vs \(frameMs(f))") }
            for d in CT.diffs(["eye": g.eye, "v": g.v] as [String: Any], ["eye": r["eye"]!, "v": wantRow(cols, r["v"] as! [Any])] as [String: Any]) { diffs.append("frame \(f) \(d)") }
        }
        CT.checkRows(label, diffs)
    }

    @MainActor static func main() {
        let m = CT.fixture("motion-cases.json"), seq = CT.fixture("sequence-cases.json")
        let cols = columns(m)
        let momo = CatPresets.byID("momo")

        CT.section("easing curves and the seeded PRNG")
        for e in m["ease"] as! [[String: Any]] {
            let curve = CatEase(rawValue: e["name"] as! String)!
            for s in e["samples"] as! [[String: Any]] { CT.checkNear("\(e["name"]!) at \(num(s["t"]))", curve.at(num(s["t"])), num(s["v"])) }
        }
        for c in m["prng"] as! [[String: Any]] {
            let seed = UInt32(truncatingIfNeeded: Int(num(c["seed"]))), r = CatRNG(seed: seed)
            CT.checkJSON("rng(\(c["seed"]!))", got: (0..<8).map { _ in r.next() }, want: c["values"]!)
        }

        CT.section("tweens")
        for c in m["tween"] as! [[String: Any]] {
            let prop = PoseKey(rawValue: c["prop"] as! String)!
            let keys: [CatKey] = (c["keys"] as! [[Any]]).map { (num($0[0]), num($0[1]), CatEase(rawValue: $0[2] as! String)!) }
            let (e, _, step) = makeEngine(momo)
            CT.checkNear("\(prop.rawValue) starts at \(num(c["from"]))", e.s[prop], num(c["from"]))
            e.anim(prop, keys)
            var got: [[Double]] = []
            for f in 0...58 { if f > 0 { step(f) }; if f % 2 == 0 { got.append([Double(f), e.s[prop]]) } }
            CT.checkJSON("\(prop.rawValue) tween", got: got, want: c["values"]!)
        }

        CT.section("rest: the targets of every state in both motion styles")
        var restDiffs: [String] = []
        for r in m["rest"] as! [[String: Any]] {
            let profile = r["profile"] as! String, st = CatState(rawValue: r["state"] as! String)!, T = num(r["T"]), look = r["look"] as! [Double]
            let (e, _, _) = makeEngine(momo, profile: profile, state: st)
            e.lookX = look[0]; e.lookY = look[1]
            e.computeTargets(T * 1000, T)
            var targets: [String: Any] = [:]
            for k in PoseKey.allCases where [PoseKey.roll, .open, .ox, .tint, .blush, .badgeS, .lift, .wh, .paws].contains(k) == false { targets[k.rawValue] = e.tg[k] }
            let got: [String: Any] = ["profile": profile, "state": st.rawValue, "T": T, "look": look, "eye": e.prof.eye(st).rawValue, "tint": CatTables.tint[st]!,
                                      "badge": CatTables.badge[st]?.rawValue ?? NSNull(), "color": CatTables.color[st]!, "glow": CatTables.glow[st] ?? NSNull(),
                                      "mfx": e.mfx, "blushBase": e.blushBase, "targets": targets]
            restDiffs += CT.diffs(got, r).map { "\(profile) \(st.rawValue) T \(T) look \(look): \($0)" }
        }
        CT.checkRows("110 rest cases", restDiffs)

        CT.section("enters: each state's entry, sampled over 3 seconds")
        let enters = m["enters"] as! [[String: Any]]
        for profile in ["playful", "classic"] {
            for st in CatState.allCases {
                let rows = enters.filter { $0["profile"] as? String == profile && $0["state"] as? String == st.rawValue }
                let got = sample(momo, profile: profile) { $0.setState(st) }
                compareRows("\(profile) \(st.rawValue)", got, rows, cols)
            }
        }

        CT.section("emotes: every emote sampled over 3 seconds (hairball 2.4 s, zoomies 2 s)")
        let emotes = m["emotes"] as! [[String: Any]]
        for profile in ["playful", "classic"] {
            for name in ["love", "happy", "surprised", "proud", "wink", "yawn", "annoyed", "hello", "zoomies", "hairball"] {
                for cat in (name == "hairball" || name == "zoomies") ? ["momo", "shrimpy"] : ["momo"] {
                    let rows = emotes.filter { $0["profile"] as? String == profile && $0["emote"] as? String == name && $0["cat"] as? String == cat }
                    let got = sample(CatPresets.byID(cat), profile: profile) { $0.emote(name) }
                    compareRows("\(profile) \(cat) \(name)", got, rows, cols)
                }
            }
        }

        CT.section("ambient: 45 s of idle habits for every personality (blinks, flicks, bleps, licks)")
        for a in m["ambient"] as! [[String: Any]] {
            let profile = a["profile"] as! String, persona = a["persona"] as! String
            var log: [[Any]] = []
            let (_, _, step) = makeEngine(momo, profile: profile, pers: ["momo": Personality.named(persona)], seed: 7, quiet: false) { log.append([$0, $1]) }
            for f in 1...(45 * 60) { step(f) }
            CT.checkJSON("\(profile) \(persona)", got: log, want: a["events"]!)
        }

        CT.section("the file catch: open wide, snap on the drop, gulp, chew (and the refused file)")
        let flightFrames = Int((380 / frameMs(1)).rounded(.up))
        CT.check("the flight lasts 23 frames", flightFrames, Int(num((seq["catchHarness"] as! [String: Any])["flightFrames"])))
        let catchFrames = [0, 6, 12, 24, 36, 48, 59, 60, 62, 66, 72, 80, 83, 84, 86, 90, 96, 108, 120, 132, 150, 168, 200, 240]
        for c in seq["catch"] as! [[String: Any]] {
            let profile = c["profile"] as! String, refused = c["refused"] as! Bool
            let (e, _, step) = makeEngine(momo, profile: profile)
            var got: [Int: (eye: String, v: [String: Any])] = [:]
            e.catchOpen(true)
            for f in 0...catchFrames.last! {
                if f > 0 { step(f) }
                if f == 60 { e.catchDrop() }
                if f == 60 + flightFrames { refused ? e.catchReject("EXE") : e.catchArrive() }
                if catchFrames.contains(f) { got[f] = (e.eyeShape().rawValue, row(e)) }
            }
            compareRows("\(profile), \(refused ? "refused (hairball)" : "taken")", got, c["rows"] as! [[String: Any]], cols)
        }

        CT.section("zoomies after five minutes of work, and on waking")
        for c in seq["zoomiesAndWake"] as! [[String: Any]] {
            let profile = c["profile"] as! String
            var log: [[Any]] = []
            let (e, clock, _) = makeEngine(momo, profile: profile) { log.append([$0, $1]) }
            // The harness moves the clock to the stated millisecond, acts, and at the end updates 60 frames.
            for item in c["script"] as! [[Any]] {
                let what = item[1] as! String
                clock.t = num(item[0])
                e.setState(what.hasPrefix("wake:") ? .idle : CatState(rawValue: what)!)
            }
            for _ in 0..<60 { clock.t += 1000 / fps; e.update(dt: 1 / fps) }
            CT.checkJSON("\(profile): \(c["name"]!)", got: log, want: c["log"]!)
        }

        CT.section("frame time comes from one clock (the old Mac engine mixed two)")
        CT.checkNear("a normal frame", CatEngine.frameDelta(now: 10.016, last: 10), 0.016)
        CT.checkNear("a clock that stepped back gives 0", CatEngine.frameDelta(now: 9, last: 10), 0)
        CT.checkNear("a long pause is held to 0.05 s", CatEngine.frameDelta(now: 100, last: 10), 0.05)
        CT.checkNear("NaN gives 0", CatEngine.frameDelta(now: .nan, last: 10), 0)
        CT.checkNear("two different clocks always gave the maximum (the bug this fixes)", CatEngine.frameDelta(now: 7.8e8, last: 12345), 0.05)
        do {
            let (e, clock, step) = makeEngine(momo)
            step(6)
            CT.checkNear("lastTime is the engine's own clock, in seconds", e.lastTime, clock.t / 1000)
            clock.t += 16
            CT.checkNear("so the next frame's dt is the 16 ms between them", CatEngine.frameDelta(now: clock.t / 1000, last: e.lastTime), 0.016)
        }

        CT.section("the mouth spring steps at most 1/60 s: a slow frame is several steps (one big step diverges to NaN)")
        do {
            let (slow, slowClock, _) = makeEngine(momo), (fast, _, fastStep) = makeEngine(momo)
            slow.catchOpen(true); fast.catchOpen(true)
            slowClock.t += 250; slow.update(dt: 0.25)
            for f in 1...15 { fastStep(f) }
            CT.checkNear("one 0.25 s update opens the mouth exactly as fifteen 1/60 s updates do", slow.slotH, fast.slotH)
            for dt in [0.066, 0.1, 0.25] {
                let (e, clock, _) = makeEngine(momo)
                e.catchDrop()
                for _ in 0..<40 { clock.t += dt * 1000; e.update(dt: dt) }
                CT.checkTrue("dt \(dt): the mouth settles near 1.05 and stays finite (\(e.slotH))", e.slotH.isFinite && abs(e.slotH - 1.05) < 0.1)
            }
        }

        CT.section("hostile frame times keep the pose finite")
        for dt in [0.0, -1, .nan, .infinity, 1e9, 0.25, 5] {
            let (e, clock, _) = makeEngine(CatPresets.byID("shrimpy"), state: .working)
            for _ in 0..<30 { clock.t += 16; e.update(dt: dt) }
            CT.checkTrue("update(dt: \(dt)) leaves every pose value finite", PoseKey.allCases.allSatisfy { e.s[$0].isFinite })
        }

        CT.section("the app-facing behaviour: pokes, dizzy, sounds, motion per cat")
        do {
            // Three quick pokes with the app's callback: the engine asks the app to go dizzy and stays as it is.
            let (e, clock, _) = makeEngine(momo)
            var dizzy = 0, sounds: [String] = []
            e.onDizzy = { dizzy += 1 }
            e.onSound = { sounds.append($0) }
            for _ in 0..<3 { clock.t += 200; e.slap(); e.update(dt: 1 / 60) }
            CT.check("the third poke calls onDizzy once", dizzy, 1)
            CT.check("and the engine did not turn dizzy by itself", e.state, CatState.idle)
            clock.t += 100; e.update(dt: 1 / 60)
            CT.check("the pokes before the third play 'slap' and, 60 ms later, 'annoyed'; the third only 'slap'", sounds, ["slap", "slap", "annoyed", "slap", "annoyed"])
        }
        do {
            let (e, clock, _) = makeEngine(momo)
            var sounds: [String] = []
            e.onSound = { sounds.append($0) }
            e.slap()
            CT.check("a poke is heard at once", sounds, ["slap"])
            clock.t += 100; e.update(dt: 1 / 60)
            CT.check("and the annoyed sound follows 60 ms later", sounds, ["slap", "annoyed"])
        }
        do {
            // Without the callback the engine turns dizzy for 3.3 s, then recovers with a happy emote.
            let (e, clock, _) = makeEngine(momo, state: .working)
            for _ in 0..<3 { clock.t += 200; e.slap() }
            CT.check("three quick pokes make the cat dizzy", e.state, CatState.dizzy)
            clock.t += 3400; e.update(dt: 1 / 60)
            CT.check("after 3.3 s it is back to what it was doing", e.state, CatState.working)
            CT.check("and happy about it", e.eyeOv, CatEye.happy)
        }
        do {
            let (e, clock, _) = makeEngine(momo)
            e.slap(); clock.t += 2000; e.slap(); clock.t += 2000; e.slap()
            CT.check("pokes more than 1.7 s apart never add up", e.state, CatState.idle)
        }
        do {
            // A kitten follows its parent's motion style and personality; a personality bends a poke.
            let cfg = CatConfig(motion: "playful", override: ["shrimpy": "classic"], pers: ["momo": Personality.named("grumpy"), "shrimpy": Personality.named("sweet")])
            let kit = CatEngine(CatPresets.kitten(of: CatPresets.byID("shrimpy")), now: { 0 }, rand: { 0.5 }, cfg: cfg, quiet: true)
            CT.check("a kitten of Shrimpy plays Shrimpy's style", kit.motion, "classic")
            CT.check("and wears Shrimpy's personality", kit.pers.preset, "sweet")
            CT.check("a sweet cat answers a poke with love", kit.pm().poke, "love")
            let other = CatEngine(momo, now: { 0 }, rand: { 0.5 }, cfg: cfg, quiet: true)
            CT.check("Momo has no override and follows the global style", other.motion, "playful")
            CT.checkTrue("a grumpy cat hisses at a poke", other.pm().pokeHiss)
            cfg.override["momo"] = "nonsense"
            CT.check("an unknown stored motion style plays Playful", other.motion, "playful")
            cfg.override["momo"] = ""
            CT.check("an empty override means the global style", other.motion, "playful")
        }
        do {
            // An unknown emote is ignored, and a gulp is a catch whose file has already flown.
            let (e, clock, step) = makeEngine(momo)
            e.emote("nonsense"); step(5)
            CT.checkTrue("an unknown emote leaves the pose finite", PoseKey.allCases.allSatisfy { e.s[$0].isFinite })
            e.gulp()
            CT.checkTrue("a gulp opens the mouth wide first", e.catching)
            clock.t += CatEngine.flightMs + 20; e.update(dt: 1 / 60)
            CT.checkTrue("and chews when the file has arrived", !e.catching && e.chewUntil > e.chewStart)
        }
        do {
            // A hairball needs to know where the mouth is: before the first draw there is nowhere to spit it, and that is not an error.
            let clock = FakeClock(), rng = CatRNG(seed: 9)
            let e = CatEngine(momo, now: { clock.t }, rand: { rng.next() }, cfg: CatConfig(), quiet: true)
            e.catchReject("EXE")
            for _ in 0..<200 { clock.t += 1000.0 / 60; e.update(dt: 1.0 / 60) }
            CT.checkTrue("a refused file before the first draw makes no ball and no crash", e.balls.isEmpty && PoseKey.allCases.allSatisfy { e.s[$0].isFinite })
        }
        do {
            // 0 % CPU when hidden starts here: a settled cat has nothing queued and nothing tweening, so there is nothing to wake for.
            let (e, clock, _) = makeEngine(momo)
            for _ in 0..<(60 * 10) { clock.t += 1000.0 / 60; e.update(dt: 1.0 / 60) }
            CT.checkTrue("after ten quiet seconds an idle cat has no queued actions and no tweens", e.q.isEmpty && e.tw.isEmpty && e.parts.isEmpty && e.balls.isEmpty)
        }
        do {
            // The music bob rides on what the renderer is given, not on the engine's own pose: the fixtures never see it.
            let (e, clock, _) = makeEngine(momo)
            for _ in 0..<120 { clock.t += 1000.0 / 60; e.update(dt: 1.0 / 60) }
            let landing = 5 * 60.0 / CatDance.bpm
            CT.checkTrue("not dancing: the look's pose is the engine's pose", e.look(time: landing).pose.pitch == e.s.pitch && e.look(time: landing).pose.earL == e.s.earL)
            e.setDancing(true)
            for _ in 0..<60 { clock.t += 1000.0 / 60; e.update(dt: 1.0 / 60) }
            CT.check("dancing for a second: the level is full", e.dancingLevel, 1)
            let bob = e.look(time: landing).pose
            CT.checkTrue("on the landing the look's head nods and its ears flop", bob.pitch < e.s.pitch - 0.1 && bob.earL > e.s.earL + 0.15)
            let before = e.s
            _ = e.look(time: landing)
            CT.checkTrue("the engine's own pose is not touched (the fixtures stay valid)", e.s == before)
            e.setDancing(false)
            for _ in 0..<60 { clock.t += 1000.0 / 60; e.update(dt: 1.0 / 60) }
            CT.checkTrue("and when the music stops it fades out", e.dancingLevel == 0 && e.look(time: landing).pose.pitch == e.s.pitch)
        }

        CT.section("the small things the reviews left for stage 7: an unknown emote, the chew's beats in a hairball, and one place for the gag's numbers")
        do {
            var notes: [(Int, String)] = []
            let (e, clock, step) = makeEngine(momo, note: { notes.append(($0, $1)) })
            e.emote("nope"); e.emote("")
            CT.check("an unknown emote is not noted, and a known one is", notes.map(\.1), [])
            e.emote("love")
            CT.check("love is", notes.map(\.1), ["emote:love"])
            CT.check("the ten emotes the panel offers are the engine's", CatTables.emoteNames, ["love", "happy", "surprised", "proud", "wink", "yawn", "annoyed", "hello", "zoomies", "hairball"])
            _ = (clock, step)
        }
        do {
            // A file is taken and chewed, and a refused one arrives while the cat is still chewing (the drop view decides at the drop, so this is two drops
            // close together): the chew's lick and sparks, queued for 0.95 s and 1 s after the first arrival, must not fire inside the hairball.
            var notes: [(Int, String)] = []
            let (e, clock, step) = makeEngine(momo, note: { notes.append(($0, $1)) })
            step(1)
            e.catchArrive()
            for f in 2...13 { step(f) }                       // 0.2 s into the chew
            let rejectAt = Int(clock.t.rounded())
            e.catchReject("EXE")
            for f in 14...200 { step(f) }
            let licks = notes.filter { $0.1 == "lick" }.map { $0.0 - rejectAt }
            CT.checkTrue("the chew's lick (0.95 s after the first arrival) is gone, and the cat licks its lips once, after the hairball starts to come up: \(licks)", licks.count == 1 && licks[0] > 1700)
            let gag = notes.first { $0.1 == "hairball" }.map { $0.0 - rejectAt } ?? -1
            CT.checkTrue("the gag takes the engine's own 120 ms (to the next frame, \(gag) ms) before the heaves start", gag >= Int(CatRules.gagMs) && gag < Int(CatRules.gagMs) + 17)
            CT.check("and the hairball lasts the engine's own 2.4 s", CatRules.hairballMs, 2400)
        }
        CT.finish()
    }
}
