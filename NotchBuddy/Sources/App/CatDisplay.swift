import Foundation

// What Settings → Cat → Display saves, and how it is cleaned: the display mode, the pair of cats of Two cats mode, and the coat of each agent. Port of the
// "Display modes: the stored settings" section of design/prototype/cat-core.js (the tie-breaker); tests/fixtures/cat/display-cases.json pins it. It is a
// clean-up of its own: `CatSettings.clean` and settings-cases.json are as they were, and the store cleans the same raw values with both. A settings file can be
// hand-edited, copied from an older build or half written, so everything read back goes through `CatDisplaySettings.clean`: raw in, clean out, never a throw.
// Foundation only. The UserDefaults keys are `cat.displayMode`, `cat.pair` (the JSON text of two cat IDs) and `cat.agentCat.<pillId>` (`CatDisplaySettings.Key`).

/// The display modes: One cat (the default and what shipped), A cat for each agent, and Two cats. Frozen contract values, like the cat IDs.
enum CatDisplayMode: String, CaseIterable, Sendable {
    case one, perAgent, two
}

struct CatDisplaySettings: Equatable, Sendable {
    /// Two cats mode's pair before the user picks: Shrimpy and Momo.
    static let defaultPair = ["shrimpy", "momo"]
    /// What an agent pill wears before the user picks: Claude Code is Shrimpy and Codex is Momo. Every other agent gets a coat when it is first seen.
    static let defaultAgentCats = ["integration_claude": "shrimpy", "agent_codex": "momo"]
    /// A stored map keeps at most this many pills (the first by code-point order of their IDs), so a hostile file cannot grow it without end.
    static let maxAgentCats = 256

    var mode: CatDisplayMode = .one
    /// The two cats of Two cats mode, cat 1 and cat 2: two valid cat IDs, never the same.
    var pair = CatDisplaySettings.defaultPair
    /// The coat each agent pill was given or picked, by pill ID.
    var agentCats: [String: String] = [:]

    // MARK: Stored words

    /// A stored mode to one of the three; anything else (a wrong case, a number, a prototype name) is One cat.
    static func modeOf(_ v: Any?) -> CatDisplayMode { (v as? String).flatMap { CatDisplayMode(rawValue: $0) } ?? .one }

    /// A pill ID: a lowercase letter, then lowercase letters, digits, `_` and `-`, 2 to 64 characters, whole (a trailing newline or space is not a pill ID: an ICU
    /// `$` would let one through). `constructor` and `prototype` are refused, as the contract does.
    static func isPillId(_ v: Any?) -> Bool {
        guard let s = v as? String, s != "constructor", s != "prototype" else { return false }
        let u = Array(s.unicodeScalars)
        guard (2...64).contains(u.count), ("a"..."z").contains(u[0]) else { return false }
        return u.dropFirst().allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_" || $0 == "-" }
    }

    /// Agent pills are Claude Code's pill (`integration_claude`, despite its prefix) and every `agent_*` pill with something after the prefix. Every other
    /// pill is an integration or an AI provider.
    static func isAgentPill(_ v: Any?) -> Bool {
        guard isPillId(v), let s = v as? String else { return false }
        return s == "integration_claude" || (s.hasPrefix("agent_") && s.count > 6)
    }

    /// The default coat of an agent pill (Claude Code Shrimpy, Codex Momo), or nil for a pill that has none.
    static func defaultAgentCat(_ id: Any?) -> String? { isPillId(id) ? defaultAgentCats[id as! String] : nil }

    static func isCatId(_ v: Any?) -> Bool { (v as? String).map { CatPresets.ids.contains($0) } ?? false }

    // MARK: Cleaning

    /// A stored pair to two cat IDs. It may be an array or the JSON text of one (the Mac stores text; text that is not strict JSON is not JSON). Anything that is
    /// not two valid cat IDs, whole, is Shrimpy and Momo. Two of the same coat make cat 2 the next coat in the 16's order (after the last one, the first).
    static func cleanPair(_ raw: Any?) -> [String] {
        var v = raw
        if let text = v as? String {
            let data = Data(text.utf8)
            v = Personality.isStrictJSON(data) ? try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) : nil
        }
        guard let a = v as? [Any], a.count == 2, a.allSatisfy(isCatId), let first = a[0] as? String, let second = a[1] as? String else { return defaultPair }
        guard first == second else { return [first, second] }
        return [first, CatPresets.ids[(CatPresets.ids.firstIndex(of: second)! + 1) % CatPresets.ids.count]]
    }

    /// A stored map from pill ID to cat ID, cleaned. A pill ID that does not have the shape of one is dropped (`__proto__` and `constructor` included); an unknown
    /// pill ID is kept, because agents come and go. A bad coat becomes the pill's default when it has one, and is dropped otherwise (the first sight of that agent
    /// gives it a coat again). The result holds at most `maxAgentCats` pills, the first in code-point order of their IDs.
    static func cleanAgentCats(_ raw: Any?) -> [String: String] {
        guard let r = raw as? [String: Any] else { return [:] }
        var out: [String: String] = [:]
        for id in r.keys.filter({ isPillId($0) }).sorted(by: { Array($0.unicodeScalars.map(\.value)).lexicographicallyPrecedes(Array($1.unicodeScalars.map(\.value))) }) {
            if out.count >= maxAgentCats { break }
            if isCatId(r[id]) { out[id] = r[id] as? String } else if let d = defaultAgentCat(id) { out[id] = d }
        }
        return out
    }

    /// Everything Display saves, cleaned. `raw` is a dictionary shaped like `{displayMode, pair, agentCats: {<pillId>: <catId>}}`; anything else gives the
    /// defaults. Never throws.
    static func clean(_ raw: Any?) -> CatDisplaySettings {
        let r = raw as? [String: Any] ?? [:]
        return CatDisplaySettings(mode: modeOf(r["displayMode"]), pair: cleanPair(r["pair"]), agentCats: cleanAgentCats(r["agentCats"]))
    }

    /// The settings as the fixtures hold them, a JSON-shaped dictionary.
    var json: [String: Any] { ["displayMode": mode.rawValue, "pair": pair, "agentCats": agentCats] }

    /// The coat an agent pill wears, as the cast reads it: the one stored for it, else its default, else the Main cat. (A coat is chosen at random only when an
    /// agent is first seen: `CatAgentCats.agentCatFor`.)
    func catFor(agent id: String, main: String) -> String { agentCats[id] ?? CatDisplaySettings.defaultAgentCat(id) ?? CatSettings.catIdOf(main) }

    // MARK: Edits

    /// What one row of Settings changes: each takes this clean value and returns a new clean one with one thing changed, and never touches its input.
    func withMode(_ m: CatDisplayMode) -> CatDisplaySettings { var s = self; s.mode = m; return s }
    /// Cat 1 (`slot` 0) or cat 2 (`slot` 1) of the pair. The pair is cleaned again, so two of the same coat make cat 2 the next one.
    func withPairCat(_ id: String, slot: Int) -> CatDisplaySettings {
        var s = self
        var next = pair
        if next.indices.contains(slot) { next[slot] = id }
        s.pair = CatDisplaySettings.cleanPair(next)
        return s
    }
    /// An agent's coat, from the picker: the map goes through the clean-up again (an unknown pill ID is kept, a bad coat is the pill's default or dropped).
    func withAgentCat(_ id: String, _ cat: String) -> CatDisplaySettings {
        var s = self
        s.agentCats = CatDisplaySettings.cleanAgentCats(agentCats.merging([id: cat]) { _, new in new })
        return s
    }

    // MARK: UserDefaults

    /// The keys: `cat.displayMode`, `cat.pair` (JSON text: `["shrimpy","momo"]`), and one `cat.agentCat.<pillId>` for each agent's coat.
    enum Key {
        static let mode = "cat.displayMode", pair = "cat.pair", agentCatPrefix = "cat.agentCat."
        static func agentCat(_ id: String) -> String { agentCatPrefix + id }
    }

    /// What is stored, cleaned. The agent coats are the keys that start with `cat.agentCat.`; each is read as the object it is, and the clean-up refuses a
    /// bad one. Nothing here can throw.
    static func load(from store: any CatSettingsBacking) -> CatDisplaySettings {
        var raw: [String: Any] = [:], cats: [String: Any] = [:]
        if let v = store.object(forKey: Key.mode) { raw["displayMode"] = v }
        if let v = store.object(forKey: Key.pair) { raw["pair"] = v }
        for key in store.allKeys() where key.hasPrefix(Key.agentCatPrefix) {
            if let v = store.object(forKey: key) { cats[String(key.dropFirst(Key.agentCatPrefix.count))] = v }
        }
        raw["agentCats"] = cats
        return clean(raw)
    }

    /// The pair as it is stored: the JSON text of two cat IDs (valid IDs are plain letters, so nothing needs escaping).
    var pairText: String { "[\"\(pair[0])\",\"\(pair[1])\"]" }

    /// Writes what differs from `old` (everything, when there is no `old`), and removes the agent-coat keys that are no longer in the map (an agent that
    /// "Reset to defaults" dropped, a key the clean-up refused). Only a cleaned value is ever passed in, so nothing that did not go through the clean-up is stored.
    func save(to store: any CatSettingsBacking, replacing old: CatDisplaySettings? = nil) {
        if old?.mode != mode { store.set(mode.rawValue, forKey: Key.mode) }
        if old?.pair != pair { store.set(pairText, forKey: Key.pair) }
        for (id, cat) in agentCats.sorted(by: { $0.key < $1.key }) where old?.agentCats[id] != cat { store.set(cat, forKey: Key.agentCat(id)) }
        for key in store.allKeys() where key.hasPrefix(Key.agentCatPrefix) && agentCats[String(key.dropFirst(Key.agentCatPrefix.count))] == nil {
            store.removeObject(forKey: key)
        }
    }
}
