import Combine
import Foundation

// The project cats' storage and rows (P-mac, Task 4): what is stored under `cat.projectCat.<catKey>`, cleaned on load and on every change, how the store saves
// only what changed, and the rows a live project and a stored one make for Settings. Foundation and Combine only, through MemoryBacking, never UserDefaults.
@main
enum ProjectCatsTests {
    typealias S = ProjectCatSettings
    typealias R = ProjectCatList

    @MainActor
    static func main() {
        CT.section("load: only a clean folder name with a cat ID is held, and reading writes nothing")
        let mem = MemoryBacking()
        mem.values = [
            "cat.projectCat.notchmeow": "momo",
            "cat.projectCat.a/b": "momo",
            "cat.projectCat.x": "Momo",
            "cat.projectCat.__proto__": "leo",
            "cat.agentCat.agent_codex": "leo",
        ]
        let keysBefore = mem.values.keys.sorted()
        CT.check("the held project cats", S.load(from: mem), ["notchmeow": "momo"])
        CT.check("a load writes nothing", mem.writes.count, 0)
        CT.checkTrue("and the backing keeps every key it had", mem.values.keys.sorted() == keysBefore)

        CT.section("the store: starts from what is stored, publishes and saves only what changed, refuses what is not a cat or a folder name")
        let store = CatSettingsStore(backing: mem, config: CatConfig())
        CT.check("the store holds what load gives", store.projectCats, ["notchmeow": "momo"])
        var seen: [[String: String]] = []
        let sub = store.$projectCats.dropFirst().sink { seen.append($0) }

        store.setProjectCat("leo", for: "site")
        CT.check("a pick is stored under its folder name, as text", mem.values["cat.projectCat.site"] as? String ?? "", "leo")
        CT.check("the store holds it and publishes the change once", [store.projectCats["site"] ?? "", "\(seen.count)"], ["leo", "1"])
        CT.check("only that key was written, and the keys nothing holds any more were removed", mem.writes, ["cat.projectCat.site"])
        CT.checkTrue("the stored keys now are the held ones", mem.values.keys.filter { $0.hasPrefix("cat.projectCat.") }.sorted() == ["cat.projectCat.notchmeow", "cat.projectCat.site"])

        let writesBeforeBogus = mem.writes.count
        store.setProjectCat("bogus", for: "site")
        CT.check("a made-up cat ID changes nothing and writes nothing", [store.projectCats["site"] ?? "", "\(mem.writes.count - writesBeforeBogus)", "\(seen.count)"], ["leo", "0", "1"])

        let writesBeforePath = mem.writes.count
        store.setProjectCat("leo", for: "a/b")
        CT.check("a folder name with a path separator stores nothing", [store.projectCats["a/b"] == nil ? "none" : "held", "\(mem.writes.count - writesBeforePath)"], ["none", "0"])

        store.resetProjectCat(for: "site")
        CT.check("reset removes the stored key and the held one, and publishes it", [mem.values["cat.projectCat.site"] == nil ? "gone" : "there", store.projectCats["site"] == nil ? "gone" : "there", "\(seen.count)"], ["gone", "gone", "2"])
        withExtendedLifetime(sub) {}

        CT.section("the cap: 257 stored keys load as the first 256 in UTF-16 order")
        let big = MemoryBacking()
        for i in 0..<257 { big.values[S.key(String(format: "p%03d", i))] = "momo" }
        let loaded = S.load(from: big)
        CT.check("256 are held", loaded.count, 256)
        CT.checkTrue("p000 and p255 are held, p256 is over the cap", loaded["p000"] == "momo" && loaded["p255"] == "momo" && loaded["p256"] == nil)

        CT.section("the cap: a pick for a 257th project is refused; it never evicts another project's stored cat")
        let full = MemoryBacking()
        for i in 0..<256 { full.values[S.key(String(format: "k%03d", i))] = "momo" }
        let fullStore = CatSettingsStore(backing: full, config: CatConfig())
        var fullSeen = 0
        let fullSub = fullStore.$projectCats.dropFirst().sink { _ in fullSeen += 1 }
        CT.check("256 are held to begin with", fullStore.projectCats.count, 256)
        fullStore.setProjectCat("leo", for: "a")   // "a" sorts before "k255", so the clean-up would keep it and drop k255
        CT.check("the new project is not stored", fullStore.projectCats["a"] == nil, true)
        CT.check("and no other project lost its cat (k255 is held, still stored)", [fullStore.projectCats["k255"] ?? "", full.values[S.key("k255")] as? String ?? "", "\(fullStore.projectCats.count)"], ["momo", "momo", "256"])
        CT.check("nothing was written and nothing published", ["\(full.writes.count)", "\(fullSeen)"], ["0", "0"])
        fullStore.setProjectCat("leo", for: "zzz")
        CT.check("a pick that sorts last is refused too: nothing written, nothing published", ["\(full.writes.count)", "\(fullSeen)", "\(fullStore.projectCats.count)"], ["0", "0", "256"])
        fullStore.setProjectCat("leo", for: "k000")
        CT.check("re-setting a stored project still works at the cap", [fullStore.projectCats["k000"] ?? "", full.values[S.key("k000")] as? String ?? "", "\(full.writes.count)", "\(fullSeen)"], ["leo", "leo", "1", "1"])
        fullStore.resetProjectCat(for: "k255")
        fullStore.setProjectCat("blue", for: "a")
        CT.check("after a Reset there is room: the new project is stored, and nobody else lost a cat", [fullStore.projectCats["a"] ?? "", "\(fullStore.projectCats.count)", fullStore.projectCats["k254"] ?? ""], ["blue", "256", "momo"])
        withExtendedLifetime(fullSub) {}

        CT.section("save: writes only the changed keys, in key order, and removes the ones no longer held")
        let sv = MemoryBacking()
        sv.values = ["cat.projectCat.a": "momo", "cat.projectCat.b": "leo"]
        S.save(["a": "momo", "b": "blue", "c": "leo"], to: sv, replacing: ["a": "momo", "b": "leo"])
        CT.check("only b and c are written", sv.writes, ["cat.projectCat.b", "cat.projectCat.c"])
        S.save(["b": "blue"], to: sv, replacing: ["a": "momo", "b": "blue", "c": "leo"])
        CT.check("a and c are removed, b is kept", sv.values.keys.filter { $0.hasPrefix("cat.projectCat.") }.sorted(), ["cat.projectCat.b"])
        CT.check("and nothing else was written", sv.writes.count, 2)

        CT.section("rows: live projects first in input order, one row per folder name; then the stored names no live project has, in UTF-16 order")
        let stored: [String: String] = ["notchmeow": "momo", "Zeta": "leo", "alpha": "blue", "gone": "puff", "bad/key": "momo", "junk": "Momo"]
        let live = [
            R.Live(catKey: "notchmeow", name: "notchmeow"),
            R.Live(catKey: "site", name: "site — web"),
            R.Live(catKey: "site", name: "site · 2"),
            R.Live(catKey: "Session", name: "Session"),
        ]
        let siteCat = ProjectsRules.projectCatOf("site", projectCats: stored, mainCat: "shrimpy").cat
        let sessionCat = ProjectsRules.projectCatOf("Session", projectCats: stored, mainCat: "shrimpy").cat
        CT.checkTrue("a picked cat is never the Main cat", siteCat != "shrimpy" && sessionCat != "shrimpy")
        let expected = [
            R.Row(catKey: "notchmeow", name: "notchmeow", cat: "momo", stored: true, live: true),
            R.Row(catKey: "site", name: "site — web", cat: siteCat, stored: false, live: true),
            R.Row(catKey: "Session", name: "Session", cat: sessionCat, stored: false, live: true),
            R.Row(catKey: "Zeta", name: "Zeta", cat: "leo", stored: true, live: false),
            R.Row(catKey: "alpha", name: "alpha", cat: "blue", stored: true, live: false),
            R.Row(catKey: "gone", name: "gone", cat: "puff", stored: true, live: false),
        ]
        CT.check("the rows of live and stored projects, with the bad keys left out", R.rows(live: live, stored: stored, main: "shrimpy"), expected)
        CT.check("with nothing live, only the stored ones", R.rows(live: [], stored: ["b": "leo", "a": "momo"], main: "shrimpy").map(\.catKey), ["a", "b"])

        CT.finish()
    }
}
