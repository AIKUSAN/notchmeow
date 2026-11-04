import Foundation

@main
enum CatSettingsStoreTests {
    /// Values of different types, as text, so one check can compare them.
    static func d(_ xs: Any...) -> [String] { xs.map { "\($0)" } }

    @MainActor static func engine(_ id: String, _ cfg: CatConfig) -> CatEngine {
        CatEngine(CatPresets.byID(id), now: { 0 }, rand: { 0.5 }, cfg: cfg, quiet: true)
    }

    /// A random source that counts its draws, on the contract's seeded generator.
    final class Dice {
        var draws = 0
        private let rng: CatRNG
        init(_ seed: UInt32) { rng = CatRNG(seed: seed) }
        func next() -> Double { draws += 1; return rng.next() }
    }

    /// H: whether the desktop cat is out, its size and its spots are held, saved and cleaned by the same store.
    @MainActor static func desktopSettings() {
        CT.section("desktop settings: the store starts from what is stored, saves only what changed and cleans what it is given")
        let laptop = DesktopCatSpots.screens([["frame": ["x": 0, "y": 0, "w": 1512, "h": 982], "visible": ["x": 0, "y": 37, "w": 1512, "h": 875], "main": true]])
        let mem = MemoryBacking()
        mem.values = ["cat.desktop.on": true, "cat.desktop.size": "large", "cat.desktop.spots": "{\"0,0,1512,982\":{\"x\":300,\"y\":400}}", "cat.character": "latte"]
        let store = CatSettingsStore(backing: mem, config: CatConfig())
        CT.check("the stored desktop settings are loaded", store.desktop, DesktopCatSettings(on: true, size: .large, spots: ["0,0,1512,982": DesktopSpot(x: 300, y: 400)]))
        CT.check("and the Cat settings beside them", store.settings.character, "latte")
        CT.check("nothing was written yet", mem.writes.count, 0)
        store.setDesktopOn(false)
        CT.check("the switch, stored as a real Bool", [store.desktop.on, mem.values["cat.desktop.on"] as? Bool ?? true], [false, false])
        store.setDesktopOn(false)
        CT.check("the same switch again writes nothing", mem.writes, ["cat.desktop.on"])
        store.setDesktopOn(true)
        CT.check("the switch back on: the store and the stored value are both the Bool true", [store.desktop.on, mem.values["cat.desktop.on"] as? Bool ?? false], [true, true])
        store.setDesktopSize(.small)
        CT.check("the size", [store.desktop.size.rawValue, mem.values["cat.desktop.size"] as? String ?? ""], ["small", "small"])
        store.rememberDesktopSpot(DesktopSpot(x: 5, y: 5), on: laptop)
        CT.check("a released spot is stored clamped, for this arrangement", [store.desktop.spots["0,0,1512,982"] == DesktopSpot(x: 48, y: 85)], [true])
        CT.check("as text with its keys in order", mem.values["cat.desktop.spots"] as? String ?? "", "{\"0,0,1512,982\":{\"x\":48,\"y\":85}}")
        store.setCharacter("momo")
        CT.check("the Main cat is another row: no desktop key moves with it", mem.writes.last ?? "", "cat.character")
        store.updateDesktop { $0.size = DesktopSize.of("Huge"); $0.spots["nonsense"] = DesktopSpot(x: 1, y: 1) }
        CT.check("a bad value is cleaned before it is stored or used", [store.desktop.size.rawValue, "\(store.desktop.spots.count)"], ["medium", "1"])
        CT.check("a second store on the same keys reads the same settings back", CatSettingsStore(backing: mem, config: CatConfig()).desktop, store.desktop)
        let wild = MemoryBacking()
        wild.values = ["cat.desktop.on": 1, "cat.desktop.size": 96, "cat.desktop.spots": 7]
        CT.check("a store that is wrong in every way still loads the defaults", CatSettingsStore(backing: wild, config: CatConfig()).desktop, DesktopCatSettings())
        CT.check("and loading wrote nothing", wild.writes.count, 0)
    }

    /// I: the stored outfit is held, saved, cycled and cleaned by the same store.
    @MainActor static func wardrobeSettings() {
        CT.section("wardrobe settings: the store starts from what is stored, saves only what changed and cleans what it is given")
        let mem = MemoryBacking()
        mem.values = ["cat.outfit": "witchhat", "cat.character": "latte"]
        let cfg = CatConfig()
        let store = CatSettingsStore(backing: mem, config: cfg)
        CT.check("the stored outfit is loaded", store.wardrobe, WardrobeSettings(outfit: "witchhat"))
        CT.check("and the Cat settings beside it", store.settings.character, "latte")
        CT.check("nothing was written yet", mem.writes.count, 0)
        CT.check("the engines' resolved outfit starts at none: the wardrobe's clock sets it, not the store", cfg.outfit, "none")
        store.setOutfit("santahat")
        CT.check("a pick is stored", [store.wardrobe.outfit, mem.values["cat.outfit"] as? String ?? ""], ["santahat", "santahat"])
        store.setOutfit("santahat")
        CT.check("the same pick again writes nothing", mem.writes, ["cat.outfit"])
        store.setOutfit("Bow")
        CT.check("a made-up name is auto, and that is what is stored", [store.wardrobe.outfit, mem.values["cat.outfit"] as? String ?? ""], ["auto", "auto"])
        store.nextOutfit()
        CT.check("the shortcut moves to the next ID: Auto goes to None", store.wardrobe.outfit, "none")
        store.nextOutfit()
        CT.check("and None to the first outfit", store.wardrobe.outfit, "partyhat")
        store.setOutfit("blossomclip")
        store.nextOutfit()
        CT.check("the last wraps to Auto", store.wardrobe.outfit, "auto")
        let outfitWritesBefore = mem.writes.filter { $0 == "cat.outfit" }.count
        store.setCharacter("momo")
        CT.check("the Main cat is another row: no wardrobe key moves with it", mem.writes.filter { $0 == "cat.outfit" }.count - outfitWritesBefore, 0)
        store.updateWardrobe { $0.outfit = "fancyhat" }
        CT.check("a bad value is cleaned before it is stored or used", store.wardrobe.outfit, "auto")
        store.setOutfit("crown")
        CT.check("a second store on the same keys reads the same choice back", CatSettingsStore(backing: mem, config: CatConfig()).wardrobe, store.wardrobe)
        let wild = MemoryBacking()
        wild.values = ["cat.outfit": 7]
        CT.check("a store that is wrong in every way still loads auto", CatSettingsStore(backing: wild, config: CatConfig()).wardrobe, WardrobeSettings())
        CT.check("and loading wrote nothing", wild.writes.count, 0)
    }

    /// B: the display mode, the pair and the agents' coats are held, saved and given out by the same store.
    @MainActor static func displaySettings() {
        CT.section("display settings: the store starts from what is stored, saves only what changed and cleans what it is given")
        let mem = MemoryBacking()
        mem.values = ["cat.displayMode": "two", "cat.pair": "[\"noodle\",\"leo\"]", "cat.agentCat.agent_zed": "snow", "cat.character": "latte"]
        let dice = Dice(5)
        let store = CatSettingsStore(backing: mem, config: CatConfig(), rand: dice.next)
        CT.check("the stored display settings are loaded", store.display, CatDisplaySettings(mode: .two, pair: ["noodle", "leo"], agentCats: ["agent_zed": "snow"]))
        CT.check("and the Cat settings beside them", store.settings.character, "latte")
        CT.check("nothing was written yet, and nothing was drawn", [mem.writes.count, dice.draws], [0, 0])
        store.setDisplayMode(.perAgent)
        CT.check("the mode", [store.display.mode.rawValue, mem.values["cat.displayMode"] as? String ?? ""], ["perAgent", "perAgent"])
        store.setDisplayMode(.perAgent)
        CT.check("the same mode again writes nothing", mem.writes, ["cat.displayMode"])
        store.setPairCat("ginger", slot: 1)
        CT.check("cat 2 of the pair, saved as JSON text", [store.display.pair.joined(separator: ","), mem.values["cat.pair"] as? String ?? ""], ["noodle,ginger", "[\"noodle\",\"ginger\"]"])
        store.setPairCat("noodle", slot: 1)
        CT.check("the same coat for both is repaired: cat 2 becomes the next coat", store.display.pair, ["noodle", "shrimpy"])
        store.setAgentCat("blue", for: "agent_zed")
        CT.check("an agent's coat, one key", [store.display.agentCats["agent_zed"] ?? "", mem.writes.last ?? ""], ["blue", "cat.agentCat.agent_zed"])
        store.setCharacter("momo")
        CT.check("the Main cat is another row: no agent's coat moves with it", [store.display.agentCats["agent_zed"] ?? "", mem.writes.last ?? ""], ["blue", "cat.character"])

        CT.section("the first sight of an agent gives it a coat once, and it keeps it")
        let first = store.ensureAgentCat(for: "agent_gemini")
        CT.checkTrue("a coat of the 16, not Shrimpy or Momo (Claude Code's and Codex's, and the Main cat is Momo), not Blue (Zed's)", CatPresets.ids.contains(first) && !["shrimpy", "momo", "blue"].contains(first))
        CT.check("it is stored, with one draw", [store.display.agentCats["agent_gemini"] ?? "", mem.values["cat.agentCat.agent_gemini"] as? String ?? "", "\(dice.draws)"], [first, first, "1"])
        let writes = mem.writes.count
        CT.check("asked again it gives the same coat, draws nothing and writes nothing", [store.ensureAgentCat(for: "agent_gemini"), "\(dice.draws)", "\(mem.writes.count - writes)"], [first, "1", "0"])
        CT.check("an integration gets the Main cat and nothing is stored or drawn", [store.ensureAgentCat(for: "integration_stripe"), "\(store.display.agentCats.count)", "\(dice.draws)"], ["momo", "2", "1"])
        CT.check("Claude Code is Shrimpy and Codex is Momo without a draw", [store.ensureAgentCat(for: "integration_claude"), store.ensureAgentCat(for: "agent_codex"), "\(dice.draws)"], ["shrimpy", "momo", "1"])
        store.rerollAgentCat(for: "agent_gemini")
        CT.checkTrue("the dice gives another coat, stores it and draws once", store.display.agentCats["agent_gemini"] != first && dice.draws == 2 && mem.values["cat.agentCat.agent_gemini"] as? String == store.display.agentCats["agent_gemini"])
        store.resetAgentCats(for: ["agent_gemini", "integration_claude", "agent_cursor"])
        CT.check("Reset to defaults: the agents in the list start again, and Zed, which was not in it, loses its coat", Set(store.display.agentCats.keys), ["agent_gemini", "agent_cursor"])
        CT.checkTrue("Zed's key is gone from the store too", mem.values["cat.agentCat.agent_zed"] == nil)

        CT.section("once at load: every agent pill that exists gets its coat, and the map is saved in one go")
        let loadMem = MemoryBacking(), loadDice = Dice(11)
        let loaded = CatSettingsStore(backing: loadMem, config: CatConfig(), rand: loadDice.next)
        loaded.ensureAgentCats(for: ["integration_claude", "agent_gemini", "agent_antigravity", "integration_stripe", "agent_gemini"])
        CT.check("two new agents, two draws, two keys", [loaded.display.agentCats.count, loadDice.draws, loadMem.writes.count], [2, 2, 2])
        CT.checkTrue("they have different coats", Set(loaded.display.agentCats.values).count == 2)
        let restartDice = Dice(99)
        let again = CatSettingsStore(backing: loadMem, config: CatConfig(), rand: restartDice.next)
        again.ensureAgentCats(for: ["agent_gemini", "agent_antigravity"])
        CT.check("a restart finds the same coats", again.display, loaded.display)
        CT.check("and draws nothing, and writes nothing", [restartDice.draws, loadMem.writes.count], [0, 2])

        CT.section("a store that is wrong in every way still loads the display settings")
        let wild = MemoryBacking()
        wild.values = ["cat.displayMode": 3, "cat.pair": "[\"momo\",", "cat.agentCat.agent_a": "tiger", "cat.agentCat.integration_claude": 9]
        let tough = CatSettingsStore(backing: wild, config: CatConfig())
        CT.check("One cat, Shrimpy and Momo, Claude Code's coat is its default and Agent A has none", tough.display, CatDisplaySettings(mode: .one, pair: ["shrimpy", "momo"], agentCats: ["integration_claude": "shrimpy"]))
    }

    @MainActor static func main() {
        CT.section("the store starts from what is stored and hands it to the engines")
        let mem = MemoryBacking()
        mem.values = ["cat.character": "momo", "cat.motionStyle": "classic", "cat.motion.shrimpy": "playful",
                      "cat.personality.momo": Personality.jsonText(Personality.named("chill"))]
        let cfg = CatConfig()
        let store = CatSettingsStore(backing: mem, config: cfg)
        CT.check("the character", [store.settings.character, cfg.character], ["momo", "momo"])
        CT.check("the global motion style", cfg.motion, "classic")
        CT.check("only the cat with its own motion has an override", cfg.override, ["shrimpy": "playful"])
        CT.check("every cat has a personality", cfg.pers.count, 16)
        CT.check("Momo is Chill", cfg.pers["momo"], Personality.named("chill"))
        CT.check("a cat that follows plays the global style, one with its own plays that", [engine("momo", cfg).motion, engine("shrimpy", cfg).motion], ["classic", "playful"])
        CT.check("a kitten plays its parent's style and wears its parent's personality", [engine("momo", cfg).pers.preset, CatEngine(CatPresets.kitten(of: CatPresets.byID("shrimpy")), now: { 0 }, rand: { 0.5 }, cfg: cfg, quiet: true).motion], ["chill", "playful"])
        CT.check("nothing was written yet", mem.writes, [])

        CT.section("a change in Settings reaches a running engine on its next frame")
        let momo = engine("momo", cfg)
        store.setMotionStyle("playful")
        CT.check("the global style", [cfg.motion, momo.motion], ["playful", "playful"])
        store.setMotionOverride("classic", for: "momo")
        CT.check("a cat's own motion", [momo.motion, engine("ginger", cfg).motion], ["classic", "playful"])
        store.setMotionOverride("follow", for: "momo")
        CT.check("and follow gives it back", momo.motion, "playful")
        store.setPreset("hyper", for: "momo")
        CT.check("a preset", d(momo.pers.preset, momo.pers.energy), d("hyper", 1.0))
        store.setTrait("sass", 0.9, for: "momo")
        CT.check("a slider turns the preset into Custom and moves one trait", d(momo.pers.preset, momo.pers.sass, momo.pers.energy), d("custom", 0.9, 1.0))
        store.setFurLines(true)
        CT.check("fur lines", [store.settings.furLines, cfg.furLines], [true, true])
        store.applyToAll(from: "momo")
        CT.check("Apply to every cat copies the personality", d(engine("noodle", cfg).pers.preset, engine("noodle", cfg).pers.sass), d("custom", 0.9))
        store.setCharacter("noodle")
        CT.check("the character", cfg.character, "noodle")

        CT.section("the collar: the style from Settings, the colour from the agent, nothing when either is missing")
        let wearer = engine("latte", cfg), kit = CatEngine(CatPresets.kitten(of: CatPresets.byID("latte")), now: { 0 }, rand: { 0.5 }, cfg: cfg, quiet: true)
        wearer.collar = "#E07950"; kit.collar = "#2DD4BF"
        CT.check("the default is off: no collar", wearer.collarPaint(dpr: 2) == nil, true)
        store.setCollar("band")
        CT.check("a global style, with the agent's colour and the pixel ratio", d(wearer.collarPaint(dpr: 2)!.style, wearer.collarPaint(dpr: 2)!.color, wearer.collarPaint(dpr: 1)!.dpr), d("band", "#E07950", 1.0))
        CT.check("a cat with no agent colour wears none (the big cat when idle)", { wearer.collar = nil; defer { wearer.collar = "#E07950" }; return wearer.collarPaint(dpr: 2) == nil }(), true)
        store.setCollarOverride("kerchief", for: "latte")
        CT.check("a cat's own style beats the global one, and the kitten wears its parent's", [wearer.collarPaint(dpr: 2)!.style, kit.collarPaint(dpr: 2)!.style, engine("momo", cfg).collarStyle], ["kerchief", "kerchief", "band"])
        store.setCollarOverride("off", for: "latte")
        CT.check("off is a style of its own: no collar on this cat while the global one is on", [wearer.collarPaint(dpr: 2) == nil, engine("momo", cfg).collarStyle == "band"], [true, true])
        store.setCollarOverride("follow", for: "latte")
        CT.check("follow gives the global style back", wearer.collarPaint(dpr: 2)!.style, "band")
        store.setCollar("scarf")
        CT.check("a style nobody knows is off", [store.settings.collar, cfg.collar], ["off", "off"])
        store.setCollar("tag"); store.setCollarOverride("band", for: "ginger"); store.applyToAll(from: "ginger")
        CT.check("Apply to every cat copies the collar too", d(store.settings.cats["noodle"]!.collar, store.settings.cats["latte"]!.collar, cfg.collarOverride.count), d("band", "band", 16))
        store.setCollar("off"); store.setCollarOverride("follow", for: "ginger"); store.applyToAll(from: "ginger")

        CT.section("what is written is only what changed, and only a cleaned value")
        let before = mem.writes.count
        store.setTrait("sass", 0.4, for: "latte")
        CT.check("one slider move writes one key", Array(mem.writes.dropFirst(before)), ["cat.personality.latte"])
        store.setTrait("sass", 0.4, for: "latte")
        CT.check("the same move again writes nothing", mem.writes.count, before + 1)
        store.update { $0.character = "tiger"; $0.motionStyle = "bogus"; $0.cats["ginger"]!.personality.energy = 7; $0.cats["ginger"]!.motion = "Classic" }
        CT.check("a bad value is cleaned before it is stored or used", d(store.settings.character, store.settings.motionStyle, store.settings.cats["ginger"]!.personality.energy, store.settings.cats["ginger"]!.motion),
                 d("shrimpy", "playful", 1.0, "follow"))
        CT.check("it is stored cleaned too: Shrimpy, and a held trait with its preset turned Custom", d(mem.values["cat.character"] ?? "-", Personality.clean(mem.values["cat.personality.ginger"]).energy, Personality.clean(mem.values["cat.personality.ginger"]).preset),
                 d("shrimpy", 1.0, "custom"))
        CT.check("the bad motion word was never written (follow is the same as no key)", mem.values["cat.motion.ginger"] == nil, true)
        CT.checkJSON("a second store on the same keys reads the same settings back", got: CatSettingsStore(backing: mem, config: CatConfig()).settings.json, want: store.settings.json)

        CT.section("a kitten is never turned into an adult: useCharacter leaves it alone")
        do {
            let kit = CatEngine(CatPresets.kitten(of: CatPresets.byID("momo")), now: { 0 }, rand: { 0.5 }, cfg: CatConfig(), quiet: true)
            kit.useCharacter("shrimpy")
            CT.check("still Momo's kitten", [kit.p.kitten == true, kit.p.base ?? ""], [true, "momo"] as [AnyHashable])
        }

        CT.section("the character switches a live engine without a restart")
        let e = engine("shrimpy", cfg)
        e.setState(.working)
        let pose = e.s
        e.useCharacter("momo")
        CT.check("Momo", e.p.name, "momo")
        CT.check("the state and the pose stay", [e.state.rawValue, "\(e.s.yaw)"], ["working", "\(pose.yaw)"])
        e.useCharacter("momo")
        e.useCharacter("tiger")
        CT.check("an unknown ID is Shrimpy", e.p.name, "shrimpy")
        displaySettings()
        desktopSettings()
        wardrobeSettings()
        CT.finish()
    }
}
