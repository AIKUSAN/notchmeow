import Foundation

@main
enum CatSettingsTests {
    typealias S = CatSettings

    static func list(_ x: Any?) -> [Any] { x as! [Any] }
    static func rows(_ x: Any?) -> [[String: Any]] { x as! [[String: Any]] }
    static func strings(_ x: Any?) -> [String] { x as! [String] }

    @MainActor static func main() {
        let fx = CT.fixture("settings-cases.json")
        let ids = CatPresets.ids

        CT.section("the frozen words: the cat IDs, follow, the two motion styles and the four collar styles")
        CT.check("the 16 cat IDs, Shrimpy first and Momo second", ids, strings(fx["ids"]))
        CT.check("follow", S.follow, fx["follow"] as! String)
        CT.check("the motion styles, in Settings order", S.motionStyles, strings(fx["motionStyles"]))
        CT.check("the collar styles, in Settings order", CatRules.collarStyles, strings(fx["collarStyles"]))
        CT.checkTrue("follow is an override, never a style", !S.motionStyles.contains(S.follow) && !CatRules.collarStyles.contains(S.follow))

        CT.section("a fresh install: Shrimpy, Playful, collar off, no fur lines, 16 cats that follow the globals and are Balanced")
        CT.checkJSON("the defaults are the fixture's", got: S().json, want: fx["defaults"]!)
        CT.checkJSON("clean(nothing) is the defaults", got: S.clean(nil).json, want: fx["defaults"]!)
        CT.check("16 cats", S().cats.count, 16)

        CT.section("cleanCatSettings: \(rows(fx["cases"]).count) stored values, from nothing to a fully valid one")
        var diffs: [String] = []
        for c in rows(fx["cases"]) {
            let d = CT.diffs(S.clean(c["raw"]).json, c["out"]!)
            if !d.isEmpty { diffs.append("\(c["name"]!): \(d.first!)") }
        }
        CT.checkRows("every case comes out as the fixture says", diffs)
        let valid = S.clean(rows(fx["cases"]).first { ($0["name"] as! String) == "a fully valid value" }!["raw"])
        CT.checkJSON("cleaning twice changes nothing", got: S.clean(valid.json).json, want: valid.json)

        CT.section("cleanPersonality: \(rows(fx["personalities"]).count) stored personalities (a string is JSON text)")
        diffs = []
        for c in rows(fx["personalities"]) {
            let d = CT.diffs(Personality.clean(c["raw"]).json, c["out"]!)
            if !d.isEmpty { diffs.append("\(c["name"]!): \(d.first!)") }
        }
        CT.checkRows("every personality comes out as the fixture says", diffs)

        CT.section("a real NaN or Infinity (JSON cannot write them, a dictionary can)")
        let wild = Personality.clean(["energy": 7, "curiosity": -2, "chatty": Double.nan, "affection": Double.infinity, "sass": -Double.infinity, "mischief": 1e300] as [String: Any])
        CT.check("traits: 7 is 1, -2 is 0, NaN and the infinities are 0.5, 1e300 is 1", [wild.energy, wild.curiosity, wild.chatty, wild.affection, wild.sass, wild.mischief], [1, 0, 0.5, 0.5, 0.5, 1])
        CT.check("a NaN trait makes the preset Custom", wild.preset, "custom")
        CT.check("a NaN in the cat's own entry is 0.5 too", S.clean(["cats": ["momo": ["personality": ["energy": Double.nan]]]]).cats["momo"]!.personality.energy, 0.5)
        CT.checkTrue("minus zero is stored as zero", Personality.clean(["energy": -0.0]).energy.sign == .plus)
        var every = true
        for p in [wild, Personality.clean(["energy": Double.nan, "curiosity": Double.nan, "chatty": Double.nan, "affection": Double.nan, "sass": Double.nan, "mischief": Double.nan])] {
            every = every && [p.energy, p.curiosity, p.chatty, p.affection, p.sass, p.mischief].allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 }
        }
        CT.checkTrue("nothing that comes out is NaN, infinite or outside 0 to 1", every)

        CT.section("JSON text is strict: Foundation's two extras are refused, and a comma inside a string is only text")
        CT.check("a comma before the closing brace is not JSON", Personality.clean("{\"energy\":0.2,}"), Personality.named("balanced"))
        CT.check("a byte-order mark is not JSON", Personality.clean("\u{FEFF}{\"energy\":0.2}"), Personality.named("balanced"))
        CT.check("a comma and a brace inside a string are only text", Personality.clean("{\"preset\":\",}\",\"energy\":0.2}").energy, 0.2)
        CT.check("so is an escaped quote followed by them", Personality.clean("{\"preset\":\"a\\\",}\",\"energy\":0.2}").energy, 0.2)
        CT.check("spaces and line breaks around the object are fine", Personality.clean(" \n{\"energy\" : 0.2 ,\n \"sass\":1}\n").sass, 1)

        CT.section("the edits of the Settings rows: each changes one thing, returns a clean value and never touches its input")
        let base = S.clean(["character": "momo", "motionStyle": "classic", "collar": "band", "furLines": true,
                            "cats": ["momo": ["motion": "playful", "collar": "off", "personality": Personality.slide(Personality.named("chill"), trait: "sass", value: 0.9).json]]])
        /// Where two settings differ, as paths of their JSON (`$.cats.momo.motion`).
        func changed(_ a: S, _ b: S) -> [String] { CT.diffs(a.json, b.json).map { String($0.prefix { $0 != ":" }) }.sorted() }
        let edits: [(String, S, [String])] = [
            ("the character", base.withCharacter("noodle"), ["$.character"]),
            ("an unknown character is Shrimpy", base.withCharacter("tiger"), ["$.character"]),
            ("the global motion style", base.withMotionStyle("playful"), ["$.motionStyle"]),
            ("follow is not a global style: Playful", base.withMotionStyle("follow"), ["$.motionStyle"]),
            ("the global collar", base.withCollar("kerchief"), ["$.collar"]),
            ("an unknown collar is off", base.withCollar("scarf"), ["$.collar"]),
            ("fur lines", base.withFurLines(false), ["$.furLines"]),
            ("a cat's own motion", base.withCatMotion("classic", for: "ginger"), ["$.cats.ginger.motion"]),
            ("a bad override is follow, which is what the cat had", base.withCatMotion("Classic", for: "ginger"), []),
            ("a cat's own collar", base.withCatCollar("tag", for: "ginger"), ["$.cats.ginger.collar"]),
            ("off is a collar override of its own", base.withCatCollar("off", for: "ginger"), ["$.cats.ginger.collar"]),
            ("an unknown cat is Shrimpy", base.withCatMotion("classic", for: "tiger"), ["$.cats.shrimpy.motion"]),
            ("a slider moves one trait and the preset", base.withPersonality(Personality.slide(base.cats["ginger"]!.personality, trait: "energy", value: 0.2), for: "ginger"), ["$.cats.ginger.personality.energy", "$.cats.ginger.personality.preset"]),
            ("a slider that is NaN changes nothing", base.withPersonality(Personality.slide(base.cats["ginger"]!.personality, trait: "energy", value: .nan), for: "ginger"), []),
        ]
        for (what, got, paths) in edits { CT.check(what, changed(base, got), paths) }
        CT.check("a preset moves the six traits of one cat and nothing else", changed(base, base.withPersonality(Personality.named("hyper"), for: "ginger")).allSatisfy { $0.hasPrefix("$.cats.ginger.personality.") }, true)
        CT.check("every edit returns a clean value", edits.allSatisfy { S.clean($0.1.json) == $0.1 }, true)
        CT.check("and the input is a value: it is as it was", base == S.clean(base.json), true)

        CT.section("Apply to every cat and the two resolvers")
        diffs = []
        for c in rows(fx["applyAll"]) {
            let out = S.clean(c["settings"]).applyingToAll(from: c["from"] as! String).json
            let d = CT.diffs(out, c["out"]!)
            if !d.isEmpty { diffs.append("\(c["name"]!): \(d.first!)") }
        }
        CT.checkRows("\(rows(fx["applyAll"]).count) apply-to-all cases", diffs)
        diffs = []
        for c in rows(fx["derived"]) {
            let s = S.clean(c["settings"]), want = c["engineCfg"] as! [String: Any]
            let cfg = s.engineCfg
            var got: [String: Any] = ["motion": cfg.motion, "override": cfg.override]
            got["pers"] = cfg.pers.mapValues { $0.json }
            diffs += CT.diffs(got, want).map { "\(c["name"]!) engineCfg: \($0)" }
            diffs += CT.diffs(ids.map { s.motion(for: $0) }, c["motionFor"]!).map { "\(c["name"]!) motionFor: \($0)" }
            diffs += CT.diffs(ids.map { s.collar(for: $0) }, c["collarFor"]!).map { "\(c["name"]!) collarFor: \($0)" }
        }
        CT.checkRows("\(rows(fx["derived"]).count) derived cases: engineCfg, motionFor and collarFor", diffs)
        var one = S()
        one.cats["momo"]!.personality = Personality.slide(Personality.named("chill"), trait: "sass", value: 0.9)
        CT.check("applying one cat to all copies the personality (Custom stays Custom)", one.applyingToAll(from: "momo").cats["noodle"]!.personality.preset, "custom")
        CT.check("an unknown cat is Shrimpy", one.applyingToAll(from: "tiger").cats["noodle"]!.personality.preset, "balanced")

        CT.section("a stored personality is read by the clean-up and never decoded")
        CT.checkTrue("CatPersonality is not Decodable", !(CatPersonality.self is Decodable.Type))
        let dir = "NotchBuddy/Sources/App"
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir).filter { $0.hasSuffix(".swift") }) ?? []
        let decoders = files.filter { f in
            let text = (try? String(contentsOfFile: dir + "/" + f, encoding: .utf8)) ?? ""
            return text.contains("decode(CatPersonality") || text.contains("decode([String: CatPersonality")
        }
        CT.check("no source decodes a CatPersonality (\(files.count) files read)", decoders, [])
        let text = Personality.jsonText(Personality.slide(Personality.named("sweet"), trait: "energy", value: 0.27))
        CT.checkJSON("the text a personality is stored as reads back the same", got: Personality.clean(text).json, want: Personality.slide(Personality.named("sweet"), trait: "energy", value: 0.27).json)
        CT.check("and its keys are sorted, so the text is the same every time", text.hasPrefix("{\"affection\":1,"), true)

        CT.section("the Cat section of Settings (source pins: no test program can run the Settings window)")
        func source(_ file: String) -> String { (try? String(contentsOfFile: "NotchBuddy/Sources/App/" + file, encoding: .utf8)) ?? "" }
        let view = source("CatSettingsView.swift"), settingsView = source("SettingsView.swift")
        CT.checkTrue("Settings has a Cat page (SettingsRoute) and shows the section", source("SettingsRoute.swift").contains("case general, agents, chat, services, cat, devices") && settingsView.contains("CatSettingsSection("))
        CT.checkTrue("the section saves nothing itself: every change goes through the store", view.contains("store.setCharacter") && !view.contains("UserDefaults") && !view.contains("@AppStorage"))
        CT.checkTrue("the previews pause when the window is not on screen", view.contains("paused: !active") && view.contains("WindowVisibility(visible: $windowVisible)"))
        CT.checkTrue("the previews are silent: they have no sound hook", !view.contains("onSound") && !view.contains("SoundEngine"))
        CT.checkTrue("Settings names the Cat section once (through CatSettingsSection, which hosts CatSettingsView with the island's agents)", settingsView.components(separatedBy: "CatSettingsSection").count == 2 && !settingsView.contains("CatSettingsView"))

        CT.section("the collar in the app (source pins): the big cat, the small cats, the greeting's cats and the Settings rows")
        let canvases = source("BotCanvasView.swift"), greetingSource = source("CatGreetingRenderer.swift")
        CT.checkTrue("the big cat's collar is the focus task's colour, none when idle", canvases.contains("engine.collar = CatRules.bigCatCollar(colour:") && canvases.contains("state.focusTask?.color"))
        CT.checkTrue("the big and the small cats hand the renderer their collar", canvases.components(separatedBy: "options.collar = engine.collarPaint(dpr:").count == 3)
        CT.checkTrue("the greeting's stand-in cats wear collars from the prototype's colours when a style is set", greetingSource.contains("miniColors") && greetingSource.contains("e.collarStyle"))
        CT.checkTrue("Settings has the two collar rows and no more than the contract's four styles", view.contains("This cat's collar") && view.contains("store.setCollar(") && view.contains("store.setCollarOverride(") && view.contains("Band and tag") && view.contains("Neckerchief"))

        CT.section("UserDefaults keys: cat.character, cat.motionStyle, cat.furLines, cat.collar, cat.motion.<id>, cat.collar.<id>, cat.personality.<id>")
        let mem = MemoryBacking()
        CT.checkJSON("an empty store loads as the defaults", got: S.load(from: mem).json, want: fx["defaults"]!)
        var s = S()
        s.character = "momo"; s.motionStyle = "classic"; s.collar = "band"; s.furLines = true
        s.cats["momo"]!.motion = "playful"; s.cats["momo"]!.collar = "off"
        s.cats["momo"]!.personality = Personality.slide(Personality.named("chill"), trait: "sass", value: 0.9)
        s.save(to: mem)
        CT.check("a first save writes every key (4 globals and 3 per cat)", mem.writes.count, 4 + 3 * 16)
        CT.check("the global keys", [mem.values["cat.character"] as? String, mem.values["cat.motionStyle"] as? String, mem.values["cat.collar"] as? String], ["momo", "classic", "band"])
        CT.check("fur lines is a real Bool", (mem.values["cat.furLines"] as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() && $0.boolValue }, true)
        CT.check("a cat's own words, follow included", [mem.values["cat.motion.momo"] as? String, mem.values["cat.collar.momo"] as? String, mem.values["cat.motion.shrimpy"] as? String], ["playful", "off", "follow"])
        CT.check("a personality is JSON text", (mem.values["cat.personality.momo"] as? String).map { $0.hasPrefix("{") }, true)
        CT.checkJSON("it loads back as it was saved", got: S.load(from: mem).json, want: s.json)
        var t = s
        t.cats["momo"]!.personality = Personality.slide(t.cats["momo"]!.personality, trait: "energy", value: 0.3)
        let before = mem.writes.count
        t.save(to: mem, replacing: s)
        CT.check("a change writes only what changed", Array(mem.writes.dropFirst(before)), ["cat.personality.momo"])
        t.save(to: mem, replacing: t)
        CT.check("and a save with nothing new writes nothing", mem.writes.count, before + 1)

        CT.section("a store that is wrong in every way still loads")
        let bad = MemoryBacking()
        bad.values = ["cat.character": 7, "cat.motionStyle": "Classic", "cat.collar": "scarf", "cat.furLines": 1, "cat.motion.momo": "bogus", "cat.collar.momo": ["tag"],
                      "cat.personality.momo": "{", "cat.personality.ginger": "{\"energy\":9,\"preset\":\"chill\"}", "cat.personality.shrimpy": Data("not json".utf8),
                      "cat.motion.tiger": "classic", "cat.personality.noodle": 42]
        let loaded = S.load(from: bad)
        CT.check("the globals fall back", [loaded.character, loaded.motionStyle, loaded.collar, "\(loaded.furLines)"], ["shrimpy", "playful", "off", "false"])
        CT.check("a bad override is follow", [loaded.cats["momo"]!.motion, loaded.cats["momo"]!.collar], ["follow", "follow"])
        CT.check("bad JSON, bytes that are not JSON and a number are Balanced", [loaded.cats["momo"]!.personality, loaded.cats["shrimpy"]!.personality, loaded.cats["noodle"]!.personality], [Personality.named("balanced"), Personality.named("balanced"), Personality.named("balanced")])
        CT.check("an out-of-range trait is held and the name no longer matches", [loaded.cats["ginger"]!.personality.energy, loaded.cats["ginger"]!.personality.chatty], [1, 0.5])
        CT.check("a preset name whose traits changed is custom", loaded.cats["ginger"]!.personality.preset, "custom")
        CT.check("there are still 16 cats and no tiger", [loaded.cats.count, loaded.cats["tiger"] == nil ? 1 : 0], [16, 1])
        CT.finish()
    }
}
