import Foundation

@main
enum CatPresetsTests {
    @MainActor static func main() {
        let want = CT.fixture("presets.json")
        let cats = want["cats"] as! [String: Any], kittens = want["kittens"] as! [String: Any]

        CT.section("the frozen IDs")
        CT.check("sixteen IDs, Shrimpy first and Momo second", CatPresets.ids, want["ids"] as! [String])
        CT.check("every ID has a coat", Set(CatPresets.all.keys), Set(CatPresets.ids))

        for id in CatPresets.ids {
            CT.section("coat \(id)")
            let p = CatPresets.byID(id)
            CT.checkJSON("coat resolves like cat-core.js", got: CT.json(p), want: cats[id]!)
            CT.checkJSON("kitten resolves like cat-core.js", got: CT.json(CatPresets.kitten(of: p)), want: kittens[id]!)
        }

        CT.section("voices (sub-project C)")
        CT.check("Shrimpy -1", CatPresets.byID("shrimpy").voice, -1)
        CT.check("Momo +1", CatPresets.byID("momo").voice, 1)
        CT.check("the extra coats 0", CatPresets.ids.dropFirst(2).map { CatPresets.byID($0).voice }, Array(repeating: 0, count: 14))
        CT.check("kittens +3", CatPresets.ids.map { CatPresets.kitten(of: CatPresets.byID($0)).voice }, Array(repeating: 3, count: 16))

        CT.section("an unknown stored ID falls back to Shrimpy")
        for bad in [nil, "", "SHRIMPY", "Momo", "siamese", "calico", "__proto__", "constructor", "momo ", "💥"] as [String?] {
            CT.check("\(bad.map { "\"\($0)\"" } ?? "nil") is Shrimpy", CatPresets.byID(bad).name, "shrimpy")
        }
        CT.check("a known ID is itself", CatPresets.byID("momo").name, "momo")

        CT.section("kittens")
        let k = CatPresets.kitten(of: CatPresets.byID("shrimpy"))
        CT.check("a kitten remembers its parent", k.base, "shrimpy")
        CT.check("a kitten is labelled", k.label, "Shrimpy kitten")
        CT.checkTrue("the parent is not changed", CatPresets.byID("shrimpy").kitten == nil && CatPresets.byID("shrimpy").rx == 1.16)
        CT.finish()
    }
}
