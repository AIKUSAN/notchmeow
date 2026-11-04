import Foundation

// What the Cat section of Settings saves, and how it is cleaned. Port of the "Stored settings" section of design/prototype/cat-core.js
// (the tie-breaker); tests/fixtures/cat/settings-cases.json pins it. A settings file can be hand-edited, copied from an older build or
// half written, so everything read back goes through `CatSettings.clean` before anything else sees it: raw in, clean out, never a throw.
// Foundation only. The UserDefaults keys are in `CatSettings.Key`, and the app's store (`CatSettingsStore`) is in its own file.

/// What the settings need from a store: `UserDefaults` in the app, a dictionary in the tests, so a test run never writes a preferences file.
protocol CatSettingsBacking {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
    /// Every key the store holds: the display settings keep one key for each agent's coat (`cat.agentCat.<pillId>`), found by their prefix.
    func allKeys() -> [String]
}

extension UserDefaults: CatSettingsBacking {
    func allKeys() -> [String] { Array(dictionaryRepresentation().keys) }
}

struct CatSettings: Equatable, Sendable {
    /// "No override: use the global setting." Stored as this word. It is not a motion style and not a collar style.
    static let follow = "follow"
    /// The motion styles, in the order Settings lists them. Playful is the default; an unknown stored style plays Playful.
    static let motionStyles = ["playful", "classic"]

    /// One cat's own settings: a motion override, a collar override (each "follow" or a style) and its personality.
    struct Entry: Equatable, Sendable {
        var motion = CatSettings.follow
        var collar = CatSettings.follow
        var personality = CatPersonality()
    }

    /// The cat shown in the notch and in the small pills. One of the 16 IDs.
    var character = "shrimpy"
    var motionStyle = "playful"
    /// The collar style for every cat: "tag", "band", "kerchief" or "off" (the default).
    var collar = "off"
    var furLines = false
    /// All 16 cats, always, by ID.
    var cats: [String: Entry] = Dictionary(uniqueKeysWithValues: CatPresets.ids.map { ($0, Entry()) })

    // MARK: Stored words

    /// A stored global motion style to "playful" or "classic"; anything else is "playful".
    static func motionStyleOf(_ v: Any?) -> String { (v as? String).flatMap { motionStyles.contains($0) ? $0 : nil } ?? "playful" }
    /// A cat's own motion: "follow", "playful" or "classic"; anything else is "follow" (no valid override).
    static func motionOverrideOf(_ v: Any?) -> String { (v as? String).flatMap { motionStyles.contains($0) ? $0 : nil } ?? follow }
    /// A cat's own collar: "follow" or one of the four styles ("off" is an override like any other); anything else is "follow".
    static func collarOverrideOf(_ v: Any?) -> String { (v as? String).flatMap { CatRules.collarStyles.contains($0) ? $0 : nil } ?? follow }
    /// A stored cat ID to one of the 16 IDs; anything else (a kitten, a wrong case, a number) is "shrimpy".
    static func catIdOf(_ v: Any?) -> String { (v as? String).flatMap { CatPresets.ids.contains($0) ? $0 : nil } ?? "shrimpy" }

    /// Fur lines are on only for a real boolean true. `1` and "true" are off: `UserDefaults.bool(forKey:)` would say yes to both, so the
    /// stored object is read as it is.
    private static func isTrue(_ v: Any?) -> Bool {
        guard let n = v as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return false }
        return n.boolValue
    }

    // MARK: Cleaning

    /// Everything Settings saves, cleaned. `raw` is a dictionary shaped like
    /// `{character, motionStyle, collar, furLines, cats: {<id>: {motion, collar, personality}}}`; anything else gives the defaults. Never throws;
    /// unknown keys and unknown cats are dropped; the result always holds all 16 cats. Each personality goes through `Personality.clean`.
    static func clean(_ raw: Any?) -> CatSettings {
        let r = raw as? [String: Any] ?? [:], stored = r["cats"] as? [String: Any] ?? [:]
        var out = CatSettings()
        out.character = catIdOf(r["character"])
        out.motionStyle = motionStyleOf(r["motionStyle"])
        out.collar = CatRules.collarStyleOf(r["collar"])
        out.furLines = isTrue(r["furLines"])
        for id in CatPresets.ids {
            let c = stored[id] as? [String: Any] ?? [:]
            out.cats[id] = Entry(motion: motionOverrideOf(c["motion"]), collar: collarOverrideOf(c["collar"]), personality: Personality.clean(c["personality"]))
        }
        return out
    }

    /// "Apply to every cat": every cat gets the motion override, collar override and personality of cat `id` (an unknown ID is Shrimpy). The
    /// character and the global settings stay. A cat that follows keeps following (what is stored is copied, not what is in force).
    func applyingToAll(from id: String) -> CatSettings {
        var out = self
        let from = cats[CatSettings.catIdOf(id)] ?? Entry()
        for c in CatPresets.ids { out.cats[c] = from }
        return out
    }

    /// The motion style a cat plays: its own override, else the global style.
    func motion(for id: String) -> String {
        let m = (cats[CatSettings.catIdOf(id)] ?? Entry()).motion
        return m == CatSettings.follow ? motionStyle : m
    }

    /// The collar style a cat wears (when it has a colour to wear): its own override, else the global style.
    func collar(for id: String) -> String {
        let c = (cats[CatSettings.catIdOf(id)] ?? Entry()).collar
        return c == CatSettings.follow ? collar : c
    }

    /// The shared settings an engine reads (the `CatConfig` fields, without the zoomies clock): the global style, an override for each cat that has
    /// one, and every cat's personality.
    struct EngineCfg: Equatable {
        var motion: String
        var override: [String: String]
        var pers: [String: CatPersonality]
    }
    var engineCfg: EngineCfg {
        var override: [String: String] = [:], pers: [String: CatPersonality] = [:]
        for id in CatPresets.ids {
            guard let c = cats[id] else { continue }
            if c.motion != CatSettings.follow { override[id] = c.motion }
            pers[id] = c.personality
        }
        return EngineCfg(motion: motionStyle, override: override, pers: pers)
    }

    /// The settings as the fixtures hold them, a JSON-shaped dictionary.
    var json: [String: Any] {
        var out: [String: Any] = [:]
        for id in CatPresets.ids {
            guard let c = cats[id] else { continue }
            out[id] = ["motion": c.motion, "collar": c.collar, "personality": c.personality.json] as [String: Any]
        }
        return ["character": character, "motionStyle": motionStyle, "collar": collar, "furLines": furLines, "cats": out]
    }

    // MARK: Edits

    /// What one row of Settings changes. Each takes this clean value and returns a new clean one with one thing changed (an unknown value is the neutral
    /// one, an unknown cat is Shrimpy, a trait is held to 0 to 1), so a row can only change its own field; the input is a value and is never touched.
    func withCharacter(_ id: String) -> CatSettings { var s = self; s.character = CatSettings.catIdOf(id); return s }
    func withMotionStyle(_ style: String) -> CatSettings { var s = self; s.motionStyle = CatSettings.motionStyleOf(style); return s }
    func withCollar(_ style: String) -> CatSettings { var s = self; s.collar = CatRules.collarStyleOf(style); return s }
    func withFurLines(_ on: Bool) -> CatSettings { var s = self; s.furLines = on; return s }
    /// "follow", "playful" or "classic" for one cat.
    func withCatMotion(_ word: String, for id: String) -> CatSettings {
        var s = self; s.cats[CatSettings.catIdOf(id)]?.motion = CatSettings.motionOverrideOf(word); return s
    }
    /// "follow" or a style for one cat ("off" is a style: this cat wears no collar while the global one is on).
    func withCatCollar(_ word: String, for id: String) -> CatSettings {
        var s = self; s.cats[CatSettings.catIdOf(id)]?.collar = CatSettings.collarOverrideOf(word); return s
    }
    /// A personality for one cat (a preset, or the result of moving a slider), cleaned.
    func withPersonality(_ p: CatPersonality, for id: String) -> CatSettings {
        var s = self; s.cats[CatSettings.catIdOf(id)]?.personality = Personality.sanitized(p.json); return s
    }

    // MARK: UserDefaults

    /// The keys: `cat.character`, `cat.motionStyle`, `cat.furLines`, `cat.collar`, and per cat `cat.motion.<id>`, `cat.collar.<id>` and
    /// `cat.personality.<id>` (the personality as JSON text).
    enum Key {
        static let character = "cat.character", motionStyle = "cat.motionStyle", furLines = "cat.furLines", collar = "cat.collar"
        static func motion(_ id: String) -> String { "cat.motion.\(id)" }
        static func collar(_ id: String) -> String { "cat.collar.\(id)" }
        static func personality(_ id: String) -> String { "cat.personality.\(id)" }
    }

    /// What is stored, cleaned. Only the keys that are there are read, and each as the object it is (a `furLines` of `1` stays a number, so the
    /// clean-up can refuse it). Nothing here can throw.
    static func load(from store: any CatSettingsBacking) -> CatSettings {
        var raw: [String: Any] = [:], cats: [String: Any] = [:]
        for (key, field) in [(Key.character, "character"), (Key.motionStyle, "motionStyle"), (Key.collar, "collar"), (Key.furLines, "furLines")] {
            if let v = store.object(forKey: key) { raw[field] = v }
        }
        for id in CatPresets.ids {
            var c: [String: Any] = [:]
            for (key, field) in [(Key.motion(id), "motion"), (Key.collar(id), "collar"), (Key.personality(id), "personality")] {
                if let v = store.object(forKey: key) { c[field] = v }
            }
            if !c.isEmpty { cats[id] = c }
        }
        raw["cats"] = cats
        return clean(raw)
    }

    /// Every stored key with the value it is stored as.
    private func stored() -> [String: AnyHashable] {
        var m: [String: AnyHashable] = [Key.character: character, Key.motionStyle: motionStyle, Key.collar: collar, Key.furLines: furLines]
        for id in CatPresets.ids {
            guard let c = cats[id] else { continue }
            m[Key.motion(id)] = c.motion; m[Key.collar(id)] = c.collar; m[Key.personality(id)] = Personality.jsonText(c.personality)
        }
        return m
    }

    /// Writes what differs from `old` (everything, when there is no `old`). `follow` is stored as the word, and a personality as the JSON text of
    /// the clean object. Only a cleaned value is ever passed in, so nothing that did not go through the clean-up is stored.
    func save(to store: any CatSettingsBacking, replacing old: CatSettings? = nil) {
        let was = old?.stored() ?? [:]
        for (key, value) in stored().sorted(by: { $0.key < $1.key }) where was[key] != value { store.set(value.base, forKey: key) }
    }
}
