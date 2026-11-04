import Foundation

// What the sidekick saves, and how it is cleaned: the master switch ("Recaps and nudges"), the local-voice switch, and how many times each kind of note was dismissed. Port of `dismiss`,
// `muted`, `unmute`, `mute` and `cleanSidekickSettings` in `shared/sidekick-core.js` (the tie-breaker); tests/fixtures/sidekick/dismiss-cases.json and settings-cases.json pin them and
// docs/SIDEKICK-CONTRACT.md explains them. A click on Not now, OK or × is a dismissal; folding the island unseen is not (the app's call). Two dismissals mute a kind; turning a kind's switch off in Settings mutes it at once (`mute`). Unmute in Settings sets
// it back to 0. The risk badge and the permission line are not a kind and are never muted. A preferences file can be hand-edited or half written, so everything read back goes through
// `SidekickSettings.clean`: raw in, clean out, never a throw. The UserDefaults keys are `sidekick.on` (a Bool), `sidekick.local` (a Bool) and `sidekick.dismissals` (the JSON text of kind to
// count). Foundation only.

struct SidekickSettings: Equatable, Sendable {
    /// The five kinds a note can be, in their frozen order. Each is dismissed and muted on its own.
    static let kinds = ["recap", "stuck.loop", "stuck.errors", "stuck.waiting", "stuck.silent"]
    static let muteAt = 2

    var on = true
    var local = true
    /// A count from 0 to 2 for every kind.
    var dismissals: [String: Int] = SidekickSettings.zeros

    static let zeros: [String: Int] = Dictionary(uniqueKeysWithValues: kinds.map { ($0, 0) })

    // MARK: Cleaning

    /// A stored count: a whole number from 1 to 2 stays (more is 2), anything else (text, a fraction, a negative, null, a boolean) is 0.
    static func cleanCount(_ v: Any?) -> Int {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return 0 }
        let d = n.doubleValue
        guard d.isFinite, d == d.rounded(), d > 0 else { return 0 }
        return d >= Double(muteAt) ? muteAt : Int(d)
    }

    /// The dismissals as they are kept: every kind once, each a count from 0 to 2. Unknown kinds go.
    static func cleanDismissals(_ raw: Any?) -> [String: Int] {
        let o = raw as? [String: Any] ?? [:]
        return Dictionary(uniqueKeysWithValues: kinds.map { ($0, cleanCount(o[$0])) })
    }

    /// A switch is on unless it is exactly the boolean false (the number 0 and the text "no" leave it on).
    private static func isOn(_ v: Any?) -> Bool {
        guard let n = v as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return true }
        return n.boolValue
    }

    /// Everything the sidekick saves, cleaned. `raw` is a dictionary shaped like `{on, local, dismissals}`; anything else gives the defaults. Never throws; cleaning twice is cleaning once.
    static func clean(_ raw: Any?) -> SidekickSettings {
        let o = raw as? [String: Any] ?? [:]
        return SidekickSettings(on: isOn(o["on"]), local: isOn(o["local"]), dismissals: cleanDismissals(o["dismissals"]))
    }

    /// The settings as the fixtures hold them, a JSON-shaped dictionary.
    var json: [String: Any] { ["on": on, "local": local, "dismissals": dismissals] }

    // MARK: Dismissals

    /// One more dismissal of a kind (a click on Not now, OK or ×). A kind that is not one of the five changes nothing.
    func dismissed(_ kind: String) -> SidekickSettings {
        var s = self
        if Self.kinds.contains(kind) { s.dismissals[kind] = min(Self.muteAt, (s.dismissals[kind] ?? 0) + 1) }
        return s
    }

    /// A kind is muted once it has been dismissed twice. A muted kind never shows.
    func isMuted(_ kind: String) -> Bool { Self.kinds.contains(kind) && (dismissals[kind] ?? 0) >= Self.muteAt }

    /// The kinds that are muted now, in the frozen order (Settings lists them).
    var mutedKinds: [String] { Self.kinds.filter(isMuted) }

    /// Unmute in Settings: that kind goes back to 0.
    func unmuted(_ kind: String) -> SidekickSettings {
        var s = self
        if Self.kinds.contains(kind) { s.dismissals[kind] = 0 }
        return s
    }

    /// A kind's switch turned off in Settings: that kind is muted at once, the same as two dismissals. A kind that is not one of the five changes nothing.
    func muting(_ kind: String) -> SidekickSettings {
        var s = self
        if Self.kinds.contains(kind) { s.dismissals[kind] = Self.muteAt }
        return s
    }

    func withOn(_ on: Bool) -> SidekickSettings { var s = self; s.on = on; return s }
    func withLocal(_ local: Bool) -> SidekickSettings { var s = self; s.local = local; return s }

    // MARK: UserDefaults

    enum Key {
        static let on = "sidekick.on", local = "sidekick.local", dismissals = "sidekick.dismissals"
    }

    /// What is stored, cleaned. Only the keys that are there are read, each as the object it is. The dismissals are stored as JSON text; text that is not JSON is no dismissals.
    static func load(from store: any CatSettingsBacking) -> SidekickSettings {
        var raw: [String: Any] = [:]
        if let v = store.object(forKey: Key.on) { raw["on"] = v }
        if let v = store.object(forKey: Key.local) { raw["local"] = v }
        if let text = store.object(forKey: Key.dismissals) as? String, let data = text.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) { raw["dismissals"] = obj }
        return clean(raw)
    }

    /// The counts as they are stored: the JSON text of kind to count, keys in order, so the same counts are always the same text.
    var dismissalsText: String {
        guard let data = try? JSONSerialization.data(withJSONObject: dismissals, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Writes what differs from `old` (everything, when there is no `old`). Only a cleaned value is ever passed in.
    func save(to store: any CatSettingsBacking, replacing old: SidekickSettings? = nil) {
        if old?.on != on { store.set(on, forKey: Key.on) }
        if old?.local != local { store.set(local, forKey: Key.local) }
        if old?.dismissals != dismissals { store.set(dismissalsText, forKey: Key.dismissals) }
    }
}
