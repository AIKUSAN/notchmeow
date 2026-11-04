import Foundation

// What the wardrobe saves (sub-project I): the stored choice `cat.outfit`. Port of `cleanWardrobeSettings` in design/prototype/cat-core.js (the tie-breaker);
// tests/fixtures/cat/wardrobe-cases.json pins it. A preferences file can be hand-edited, so everything read back goes through `WardrobeSettings.clean`: raw in, clean out, never a
// throw. It is a clean-up of its own, as `DesktopCatSettings.clean` is: the Cat, Display and Desktop clean-ups and their fixtures are as they were. Foundation only.

struct WardrobeSettings: Equatable, Sendable {
    /// One of the 18 IDs. `auto` is a choice, not an outfit: the clock resolves it for drawing (`WardrobeClock`).
    var outfit = Wardrobe.defaultOutfit

    // MARK: Cleaning

    /// Everything the wardrobe saves, cleaned. `raw` is a dictionary shaped like `{outfit}`; anything else gives the default. Never throws.
    static func clean(_ raw: Any?) -> WardrobeSettings {
        let r = raw as? [String: Any] ?? [:]
        return WardrobeSettings(outfit: Wardrobe.idOf(r["outfit"]))
    }

    /// The settings as the fixtures hold them.
    var json: [String: Any] { ["outfit": outfit] }

    // MARK: Edits

    func withOutfit(_ id: String) -> WardrobeSettings { WardrobeSettings(outfit: Wardrobe.idOf(id)) }

    // MARK: UserDefaults

    enum Key { static let outfit = "cat.outfit" }

    /// What is stored, cleaned. The stored object is read as it is, so a number or a list is `auto`.
    static func load(from store: any CatSettingsBacking) -> WardrobeSettings {
        var raw: [String: Any] = [:]
        if let v = store.object(forKey: Key.outfit) { raw["outfit"] = v }
        return clean(raw)
    }

    /// Writes what differs from `old` (everything, when there is no `old`). Only a cleaned value is ever passed in.
    func save(to store: any CatSettingsBacking, replacing old: WardrobeSettings? = nil) {
        if old?.outfit != outfit { store.set(outfit, forKey: Key.outfit) }
    }
}
