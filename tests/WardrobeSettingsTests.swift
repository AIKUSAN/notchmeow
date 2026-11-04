import Foundation

@main
enum WardrobeSettingsTests {
    static func rows(_ x: Any?) -> [[String: Any]] { x as! [[String: Any]] }

    @MainActor static func main() {
        let fx = CT.fixture("wardrobe-cases.json")

        CT.section("the frozen values: the 18 IDs in order, their names, the grid's rows, the 16 that are drawn, the default and the roles")
        CT.check("the IDs, in order", Wardrobe.ids, fx["ids"] as! [String])
        CT.check("the names", Wardrobe.names, fx["names"] as! [String: String])
        func line(_ id: String, _ name: String, _ ids: [String]) -> String { id + "|" + name + "|" + ids.joined(separator: ",") }
        CT.check("the grid's rows", Wardrobe.groups.map { line($0.id, $0.name, $0.ids) }, rows(fx["groups"]).map { line($0["id"] as! String, $0["name"] as! String, $0["ids"] as! [String]) })
        CT.check("the 16 that are drawn", Wardrobe.drawn, fx["drawn"] as! [String])
        CT.check("the default", Wardrobe.defaultOutfit, fx["defaultOutfit"] as! String)
        CT.check("the roles", Wardrobe.roles, fx["roles"] as! [String])
        CT.check("the groups hold each ID once, in the IDs' order", Wardrobe.groups.flatMap(\.ids), Wardrobe.ids)

        CT.section("idOf: \(rows(fx["clean"]).count) stored values")
        var diffs: [String] = []
        for c in rows(fx["clean"]) where Wardrobe.idOf(c["input"]) != c["out"] as! String { diffs.append("\(c["name"] as! String): \(Wardrobe.idOf(c["input"]))") }
        CT.checkRows("every stored value is as the fixture says (an ID exactly as written is kept, everything else is auto)", diffs)

        CT.section("WardrobeSettings.clean: \(rows(fx["settings"]).count) stored blocks")
        diffs = []
        for c in rows(fx["settings"]) {
            let d = CT.diffs(WardrobeSettings.clean(c["input"]).json, c["out"] ?? NSNull())
            if !d.isEmpty { diffs.append("\(c["name"] as! String): \(d.first!)") }
        }
        CT.checkRows("every block is as the fixture says, and only the `outfit` key is read", diffs)

        CT.section("who wears it: \(rows(fx["worn"]).count) roles")
        diffs = []
        for c in rows(fx["worn"]) where Wardrobe.worn(c["role"]) != c["out"] as! Bool { diffs.append("\(String(describing: c["role"])): \(Wardrobe.worn(c["role"]))") }
        CT.checkRows("only the text big is worn, whatever else it is called", diffs)
        CT.check("the app's three roles", [Wardrobe.worn(Wardrobe.Role.big), Wardrobe.worn(Wardrobe.Role.small), Wardrobe.worn(Wardrobe.Role.kitten)], [true, false, false])

        CT.section("the ⌃⌥G cycle: the grid's order, Auto and None included")
        var walk = ["auto"]
        for _ in 0..<17 { walk.append(Wardrobe.next(after: walk.last!)) }
        CT.check("eighteen presses visit every ID once, in the grid's order", walk, Wardrobe.ids)
        CT.check("and the next one wraps from blossomclip to auto", Wardrobe.next(after: "blossomclip"), "auto")
        CT.check("Auto goes to None", Wardrobe.next(after: "auto"), "none")
        CT.check("an ID that is not one counts as Auto, so the next is None", Wardrobe.next(after: "fancyhat"), "none")

        CT.section("the UserDefaults key, through a dictionary store")
        let store = MemoryBacking()
        CT.check("an empty store loads auto", WardrobeSettings.load(from: store), WardrobeSettings())
        store.values = ["cat.outfit": "crown", "cat.character": "momo"]
        let loaded = WardrobeSettings.load(from: store)
        CT.check("what is stored is loaded (and the other cat keys are not read)", loaded, WardrobeSettings(outfit: "crown"))
        let fresh = MemoryBacking()
        loaded.save(to: fresh)
        CT.check("the one key it writes", fresh.writes, ["cat.outfit"])
        CT.check("and loads back as it was", WardrobeSettings.load(from: fresh), loaded)
        let before = fresh.writes.count
        loaded.save(to: fresh, replacing: loaded)
        CT.check("nothing that did not change is written", fresh.writes.count, before)
        loaded.withOutfit("bow").save(to: fresh, replacing: loaded)
        CT.check("a change writes the key again", Array(fresh.writes[before...]), ["cat.outfit"])
        CT.check("an edit with a made-up name is auto", loaded.withOutfit("Crown"), WardrobeSettings(outfit: "auto"))

        CT.section("a store that is wrong in every way still loads")
        let wild = MemoryBacking()
        for (label, value) in [("a number", 7 as Any), ("a list", ["bow"] as Any), ("data", Data("bow".utf8) as Any), ("a boolean", true as Any), ("a capital", "Bow" as Any), ("padding", " bow " as Any)] {
            wild.values = ["cat.outfit": value]
            CT.check("\(label) is auto", WardrobeSettings.load(from: wild), WardrobeSettings())
        }

        CT.section("the menus' items")
        let items = WardrobeMenu.items(selected: "scarf", autoToday: "santahat")
        let choices = items.compactMap { i -> (String, String, Bool)? in if case .choice(let id, let t, let c) = i { return (id, t, c) } else { return nil } }
        CT.check("the 18 choices in the grid's order", choices.map(\.0), Wardrobe.ids)
        CT.check("one is ticked: the stored one", choices.filter(\.2).map(\.0), ["scarf"])
        CT.check("Auto's label shows today's result", choices[0].1, "Auto: today, Santa hat")
        CT.check("and None's is its name", choices[1].1, "None")
        CT.check("a day with nothing to wear says none", WardrobeMenu.items(selected: "auto", autoToday: "none").compactMap { i -> String? in if case .choice("auto", let t, _) = i { return t } else { return nil } }, ["Auto: today, none"])
        CT.check("the headings are the four groups', and the groups are set apart", items.compactMap { i -> String? in if case .heading(let h) = i { return h } else { return nil } }, ["Seasonal", "Everyday", "Cat extras", "The cats' own"])
        CT.check("four separators", items.filter { $0 == .separator }.count, 4)
        CT.check("a stored value that is not an ID ticks Auto", WardrobeMenu.items(selected: "nope", autoToday: "none").compactMap { i -> String? in if case .choice(let id, _, true) = i { return id } else { return nil } }, ["auto"])
        CT.finish()
    }
}
