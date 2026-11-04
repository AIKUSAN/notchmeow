import Foundation

// What the desktop cat saves, and how it is cleaned: whether it is out, its size, and its spot for each arrangement of screens. Port of `cleanDesktopSettings` in
// design/prototype/cat-core.js (the tie-breaker); tests/fixtures/cat/desktop-cases.json pins it. It is a clean-up of its own, as `CatDisplaySettings.clean` is: `CatSettings.clean`,
// `CatDisplaySettings.clean` and every line of their fixtures are as they were, and the store cleans the same stored block with each function it needs. A preferences file can be
// hand-edited or half written, so everything read back goes through `DesktopCatSettings.clean`: raw in, clean out, never a throw. The UserDefaults keys are `cat.desktop.on` (a
// Bool), `cat.desktop.size` (`small`, `medium` or `large`) and `cat.desktop.spots` (the JSON text of the map): `DesktopCatSettings.Key`. Foundation only.

struct DesktopCatSettings: Equatable, Sendable {
    /// Whether the cat is out on the desktop. The trip stores `DESKTOP_PHASE_INFO[phase].on`, so quitting mid-flight home leaves the cat in the notch.
    var on = false
    var size = DesktopSize.medium
    /// The spot remembered for each arrangement of screens, by `DesktopCatSpots.screenKey`.
    var spots: [String: DesktopSpot] = [:]

    // MARK: Cleaning

    /// `true` only for the boolean true: the number 1 and the text "true" are off (`UserDefaults.bool(forKey:)` would turn both into true, so the stored object is read as it is).
    static func isTrue(_ v: Any?) -> Bool {
        guard let n = v as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return false }
        return n.boolValue
    }

    /// Everything the desktop cat saves, cleaned. `raw` is a dictionary shaped like `{on, size, spots}`; anything else gives the defaults. Never throws.
    static func clean(_ raw: Any?) -> DesktopCatSettings {
        let r = raw as? [String: Any] ?? [:]
        return DesktopCatSettings(on: isTrue(r["on"]), size: DesktopSize.of(r["size"]), spots: DesktopCatSpots.cleanSpots(r["spots"]))
    }

    /// The settings as the fixtures hold them, a JSON-shaped dictionary.
    var json: [String: Any] { ["on": on, "size": size.rawValue, "spots": spots.mapValues { ["x": $0.x, "y": $0.y] } as [String: Any]] }

    // MARK: Edits

    /// What one control changes: each takes this clean value and returns a new clean one with one thing changed, and never touches its input.
    func withOn(_ on: Bool) -> DesktopCatSettings { var s = self; s.on = on; return s }
    func withSize(_ size: DesktopSize) -> DesktopCatSettings { var s = self; s.size = size; return s }
    /// The cat was released at `spot`: this arrangement's spot is the clamped one (`DesktopCatSpots.rememberSpot`).
    func remembering(_ spot: DesktopSpot, on screens: [DesktopScreen]) -> DesktopCatSettings {
        var s = self
        s.spots = DesktopCatSpots.rememberSpot(spots, screens, spot, size: size)
        return s
    }
    /// The spot to put the cat on now (`DesktopCatSpots.spotFor`).
    func spot(on screens: [DesktopScreen]) -> DesktopSpot? { DesktopCatSpots.spotFor(spots, screens, size: size) }

    // MARK: UserDefaults

    enum Key {
        static let on = "cat.desktop.on", size = "cat.desktop.size", spots = "cat.desktop.spots"
    }

    /// What is stored, cleaned. Only the keys that are there are read, each as the object it is (an `on` of `1` stays a number, so it is off). Nothing here can throw.
    static func load(from store: any CatSettingsBacking) -> DesktopCatSettings {
        var raw: [String: Any] = [:]
        for (key, field) in [(Key.on, "on"), (Key.size, "size"), (Key.spots, "spots")] { if let v = store.object(forKey: key) { raw[field] = v } }
        return clean(raw)
    }

    /// The map as it is stored: the JSON text of screen key to `{x, y}`, keys in order, so the same map is always the same text.
    var spotsText: String {
        let object = spots.mapValues { ["x": $0.x, "y": $0.y] } as [String: Any]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Writes what differs from `old` (everything, when there is no `old`). Only a cleaned value is ever passed in, so nothing that did not go through the clean-up is stored.
    func save(to store: any CatSettingsBacking, replacing old: DesktopCatSettings? = nil) {
        if old?.on != on { store.set(on, forKey: Key.on) }
        if old?.size != size { store.set(size.rawValue, forKey: Key.size) }
        if old?.spots != spots { store.set(spotsText, forKey: Key.spots) }
    }
}
