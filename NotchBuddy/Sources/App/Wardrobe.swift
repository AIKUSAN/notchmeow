import Foundation

// The wardrobe's frozen names (sub-project I). Port of the "wardrobe" section of design/prototype/cat-core.js (the tie-breaker): the 18 selection IDs and their order, `outfitIdOf`
// and `outfitWorn`; tests/fixtures/cat/wardrobe-cases.json pins them. The IDs and their order are frozen, because they are stored (`cat.outfit`) and because the grid, the menus and the
// ⌃⌥G cycle all follow the order. Foundation only, and nothing else: the renderer files compile it without the settings.

enum Wardrobe {
    /// The 18 selection IDs: Auto, None, then the 16 outfits in the grid's order. Frozen.
    static let ids = ["auto", "none", "partyhat", "santahat", "witchhat", "bunnyears", "sunglasses", "beanie", "bow", "scarf", "roundglasses", "crown", "bell", "bandana", "fishclip", "flower", "shrimpclip", "blossomclip"]
    /// The names the UI shows, by ID.
    static let names: [String: String] = [
        "auto": "Auto", "none": "None", "partyhat": "Party hat", "santahat": "Santa hat", "witchhat": "Witch hat", "bunnyears": "Bunny ears", "sunglasses": "Sunglasses",
        "beanie": "Beanie", "bow": "Bow", "scarf": "Scarf", "roundglasses": "Round glasses", "crown": "Crown", "bell": "Bell", "bandana": "Bandana", "fishclip": "Fish clip",
        "flower": "Flower", "shrimpclip": "Shrimp clip", "blossomclip": "Peach-blossom clip",
    ]
    /// The grid's rows: the two choices (no heading), then the four groups with their headings.
    struct Group: Equatable, Sendable { var id: String; var name: String; var ids: [String] }
    static let groups = [
        Group(id: "choice", name: "", ids: ["auto", "none"]),
        Group(id: "seasonal", name: "Seasonal", ids: ["partyhat", "santahat", "witchhat", "bunnyears", "sunglasses"]),
        Group(id: "everyday", name: "Everyday", ids: ["beanie", "bow", "scarf", "roundglasses", "crown"]),
        Group(id: "extras", name: "Cat extras", ids: ["bell", "bandana", "fishclip", "flower"]),
        Group(id: "own", name: "The cats' own", ids: ["shrimpclip", "blossomclip"]),
    ]
    /// The 16 that are drawn: everything but Auto and None.
    static let drawn = Array(ids.dropFirst(2))
    static let defaultOutfit = "auto"

    /// The name to show for an ID ("Auto" for anything that is not one).
    static func name(_ id: String) -> String { names[id] ?? "Auto" }

    /// A stored outfit to an ID: exactly one of the 18, as written (lowercase, no trimming); anything else, or no string at all, is "auto".
    static func idOf(_ v: Any?) -> String {
        guard let s = v as? String, ids.contains(s) else { return defaultOutfit }
        return s
    }

    /// The next ID in the grid's order, `auto` and `none` included, wrapping from `blossomclip` to `auto` (⌃⌥G). An ID that is not one counts as `auto`.
    static func next(after id: String) -> String {
        let i = ids.firstIndex(of: idOf(id)) ?? 0
        return ids[(i + 1) % ids.count]
    }

    /// Who wears an outfit: the cats in a big-cat role, at every size. The role decides, never the diameter.
    enum Role: String, Sendable { case big, small, kitten }
    static let roles = ["big", "small", "kitten"]
    /// `outfitWorn`: true for the text "big" and nothing else (a diameter, `null`, a wrong case and a made-up role are all bare).
    static func worn(_ role: Any?) -> Bool { (role as? String) == "big" }
    static func worn(_ role: Role) -> Bool { role == .big }
}
