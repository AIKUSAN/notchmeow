import Foundation

@main
enum CatDevModelTests {
    @MainActor static func main() {
        let clock = FakeClock(), rng = CatRNG(seed: 2)
        func model() -> CatDevModel { CatDevModel(now: { clock.t }, rand: { rng.next() }) }

        CT.section("the panel starts on Shrimpy, big, Playful and idle")
        let m = model()
        CT.check("coat", m.coat, "shrimpy"); CT.check("not a kitten", m.kitten, false); CT.check("size", m.size, 66)
        CT.check("motion style", m.motion, "playful"); CT.check("state", m.state, CatState.idle)
        CT.check("the stage cat is Shrimpy", m.stage.p.name, "shrimpy")
        CT.check("eleven small cats, one per state, in the contract's order", m.strip.map(\.state), CatState.allCases)
        CT.check("the marker the binary check looks for", CatDevModel.marker, "NM_CAT_DEV_PANEL")

        CT.section("every coat, as a cat and as a kitten, builds a stage cat and eleven small cats")
        for id in CatPresets.ids {
            for k in [false, true] {
                m.pick(coat: id); m.pick(kitten: k)
                CT.checkTrue("\(id)\(k ? " kitten" : ""): the stage cat and all eleven small ones wear it",
                             m.stage.p.name == id && m.stage.p.kitten == (k ? true : nil) && m.strip.count == 11 && m.strip.allSatisfy { $0.p.name == id && ($0.p.kitten ?? false) == k })
            }
        }
        m.pick(kitten: false)

        CT.section("an unknown coat is Shrimpy and an unknown size is Ø66")
        for bad in ["", "SHRIMPY", "siamese", "💥"] { m.pick(coat: bad); CT.check("\"\(bad)\" is Shrimpy", m.coat, "shrimpy") }
        m.pick(size: 12); CT.check("Ø12 is offered", m.size, 12)
        m.pick(size: 13); CT.check("Ø13 is not: Ø66", m.size, 66)
        CT.check("the sizes run from the mini pill to a close look", [CatDevModel.sizes.first!, CatDevModel.sizes.last!], [12, 180])

        CT.section("a state moves the stage cat only")
        m.pick(state: .approval)
        CT.check("the stage cat is in approval", m.stage.state, CatState.approval)
        CT.check("the small cats stay in their own states", m.strip.map(\.state), CatState.allCases)
        m.pick(coat: "momo")
        CT.check("a new coat keeps the chosen state", m.stage.state, CatState.approval)

        CT.section("a motion style applies to every engine, and an unknown one plays Playful")
        m.pick(motion: "classic")
        CT.checkTrue("the stage cat and the eleven small ones play Classic", ([m.stage] + m.strip).allSatisfy { $0.motion == "classic" })
        m.pick(motion: "nonsense")
        CT.check("an unknown style is Playful", m.motion, "playful")
        CT.checkTrue("and every engine follows", ([m.stage] + m.strip).allSatisfy { $0.motion == "playful" })

        CT.section("the panel never touches the app's own settings")
        CT.check("the shared style is as it was", CatConfig.shared.motion, "playful")
        CT.checkTrue("and it holds no override and no personality", CatConfig.shared.override.isEmpty && CatConfig.shared.pers.isEmpty)
        m.pick(motion: "classic")
        CT.check("even after the panel chose Classic", CatConfig.shared.motion, "playful")

        CT.section("emotes: every emote plays on the stage cat, and the panel notes it")
        m.pick(coat: "momo"); m.pick(motion: "playful")
        CT.check("ten emotes, hairball and zoomies among them", CatDevModel.emotes, ["love", "happy", "surprised", "proud", "wink", "yawn", "annoyed", "hello", "zoomies", "hairball"])
        for name in CatDevModel.emotes {
            m.emote(name)
            CT.checkTrue("\(name) is noted", m.notes.contains("emote:\(name)"))
        }
        CT.checkTrue("the notes keep the last eight, the newest last", m.notes.count == 8 && Array(m.notes.suffix(2)) == ["emote:hairball", "hairball"])
        m.emote("nonsense")
        CT.checkTrue("an unknown emote leaves the pose finite", PoseKey.allCases.allSatisfy { m.stage.s[$0].isFinite })
        CT.checkTrue("and is not noted", !m.notes.contains("emote:nonsense"))
        CT.check("the panel offers the engine's emotes", CatDevModel.emotes, CatTables.emoteNames)

        CT.section("personality: a preset applies to the stage cat and the small ones, and follows the coat")
        m.pick(personality: "grumpy")
        CT.checkTrue("a grumpy cat hisses at a poke, on the stage and in the strip", ([m.stage] + m.strip).allSatisfy { $0.pm().pokeHiss })
        m.pick(coat: "ginger")
        CT.check("the personality follows the coat", m.personality, "grumpy")
        CT.checkTrue("and the new coat is grumpy", m.stage.pm().pokeHiss)
        m.pick(personality: "sweet")
        CT.check("a sweet cat answers a poke with love", m.stage.pm().poke, "love")
        m.pick(personality: "nonsense")
        CT.check("an unknown personality is Balanced", m.personality, "balanced")
        CT.checkTrue("and every engine follows", ([m.stage] + m.strip).allSatisfy { !$0.pm().pokeHiss && $0.pm().poke == "annoyed" })
        m.pick(personality: "grumpy"); m.pick(kitten: true)
        CT.checkTrue("a kitten wears its parent's personality", m.stage.pm().pokeHiss)
        m.pick(kitten: false); m.pick(personality: "balanced")
        CT.checkTrue("the app's own cats have no personality of the panel's", CatConfig.shared.pers.isEmpty)

        CT.section("a poke: three quick ones make the cat dizzy, then it recovers")
        m.pick(state: .idle)
        for _ in 0..<3 { clock.t += 200; m.poke() }
        CT.check("three quick pokes make the stage cat dizzy", m.stage.state, CatState.dizzy)
        CT.check("the state the panel chose is as it was", m.state, CatState.idle)
        clock.t += 3400; m.stage.update(dt: 1.0 / 60)
        CT.check("and after 3.3 s it is back", m.stage.state, CatState.idle)

        CT.section("a thrown file: the app's own rule decides at the drop, the flight is 380 ms, and the cat chews it or coughs it up")
        for (name, size, refused) in [("notes.pdf", 80_000, false), ("setup.exe", 5_000_000, true), ("clip.mov", 5, true), ("export.txt", 30 * 1_048_576, true), ("exactly.txt", 26_214_400, false), ("folder", 0, false)] {
            let t = model()
            t.pick(coat: "momo")
            t.catchFile(named: name, size: size)
            CT.checkTrue("\(name): the cat opens wide at once", t.stage.catching)
            clock.t += 100; t.advance()
            CT.checkTrue("\(name): the file has not dropped at 0.1 s", t.flight == nil)
            clock.t += 400; t.advance()
            CT.checkTrue("\(name): it dropped at 0.42 s and is in flight, refused or not as the rule says", t.flight != nil && t.flight?.refused == refused)
            CT.checkTrue("\(name): the flight is under way", (t.flightProgress ?? -1) >= 0 && (t.flightProgress ?? 2) < 1)
            clock.t += CatEngine.flightMs + 10; t.advance()
            CT.checkTrue("\(name): it lands after 380 ms", t.flight == nil && t.flightProgress == nil)
            for _ in 0..<150 { clock.t += 1000.0 / 60; t.stage.update(dt: 1.0 / 60) }
            CT.check("\(name): a refused file is coughed up as a hairball, a taken one chewed", [t.notes.contains("hairball"), t.stage.chewUntil > 0], [refused, !refused])
        }
        CT.check("the panel offers a PDF, an app and a 30 MB file", CatDevModel.files.map(\.name), ["notes.pdf", "setup.exe", "export.txt"])
        CT.check("and the app's rule refuses the last two", CatDevModel.files.map { CatFileRule.refused(ext: ($0.name as NSString).pathExtension, size: $0.size) }, [false, true, true])

        CT.section("the greeting's cat is the chosen cat")
        m.pick(coat: "latte")
        CT.check("the greeting engine wears the coat", m.greeting.p.name, "latte")
        m.pick(kitten: true)
        CT.checkTrue("and its kitten", m.greeting.p.kitten == true)
        m.pick(kitten: false)

        CT.section("the collar and the fur lines: the panel's own settings, never the app's")
        let c = model()
        CT.check("the panel starts with no collar and no fur", [c.collar, "\(c.fur)"], ["off", "false"])
        CT.check("four collar styles, Off among them, and the agents' colours", [CatDevModel.collars.map(\.id), CatDevModel.agents.map(\.hex)], [["tag", "band", "kerchief", "off"], ["#E07950", "#8AB4F8", "#2DD4BF", "#E879F9", "#C0C4CC", "#F5F6F8"]])
        c.pick(collar: "band")
        CT.checkTrue("a style reaches the stage cat and the eleven small ones, in the agent's colour", ([c.stage] + c.strip).allSatisfy { $0.collarPaint(dpr: 2)?.style == "band" && $0.collarPaint(dpr: 2)?.color == "#E07950" })
        c.pick(agent: 2)
        CT.checkTrue("another agent colours them all", ([c.stage] + c.strip).allSatisfy { $0.collarPaint(dpr: 2)?.color == "#2DD4BF" })
        c.pick(coat: "momo"); c.pick(kitten: true)
        CT.checkTrue("a new coat or a kitten keeps the collar", ([c.stage] + c.strip + [c.greeting]).allSatisfy { $0.collarPaint(dpr: 2)?.style == "band" && $0.collarPaint(dpr: 2)?.color == "#2DD4BF" })
        c.pick(collar: "scarf"); c.pick(agent: 99)
        CT.check("a style nobody knows is off, an agent nobody knows is the first", [c.collar, CatDevModel.agents[c.agent].hex], ["off", "#E07950"])
        CT.check("the app's own settings stay as they were", [CatConfig.shared.collar, "\(CatConfig.shared.furLines)", "\(CatConfig.shared.collarOverride.count)"], ["off", "false", "0"])

        CT.section("the engines run: every pose stays finite after ten seconds")
        for e in [m.stage] + m.strip { for _ in 0..<(60 * 10) { clock.t += 1000.0 / 60; e.update(dt: 1.0 / 60) } }
        CT.checkTrue("twelve cats, all finite", ([m.stage] + m.strip).allSatisfy { e in PoseKey.allCases.allSatisfy { e.s[$0].isFinite } })
        CT.finish()
    }
}
