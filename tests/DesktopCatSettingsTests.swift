import Foundation

@main
enum DesktopCatSettingsTests {
    typealias S = DesktopCatSpots
    typealias Cfg = DesktopCatSettings

    static func rows(_ x: Any?) -> [[String: Any]] { x as! [[String: Any]] }
    /// A fixture spot (`{x, y}` or null) as JSON, for comparing.
    static func spotJSON(_ s: DesktopSpot?) -> Any { s.map { ["x": $0.x, "y": $0.y] as [String: Any] } ?? NSNull() }
    static func mapJSON(_ m: [String: DesktopSpot]) -> [String: Any] { m.mapValues { ["x": $0.x, "y": $0.y] as [String: Any] } }

    @MainActor static func main() {
        let fx = CT.fixture("desktop-cases.json")

        CT.section("the frozen values: the three sizes, the margin, the default spot and the cap")
        let sizes = fx["sizes"] as! [String: Any]
        CT.check("the size IDs, in order", DesktopSize.allCases.map(\.rawValue), fx["sizeIds"] as! [String])
        CT.check("the head widths", DesktopSize.allCases.map(\.d), DesktopSize.allCases.map { (sizes[$0.rawValue] as! NSNumber).doubleValue })
        CT.check("the default size", DesktopSize.of(nil).rawValue, fx["defaultSize"] as! String)
        CT.checkNear("the margin", S.margin, (fx["margin"] as! NSNumber).doubleValue)
        let ds = fx["defaultSpot"] as! [String: Any]
        CT.checkNear("the default spot across", S.defaultAcross, (ds["x"] as! NSNumber).doubleValue)
        CT.checkNear("and down (a third)", S.defaultDown, (ds["y"] as! NSNumber).doubleValue, tol: 1e-9)
        CT.check("at most 32 arrangements are remembered", S.maxSpots, fx["maxSpots"] as! Int)

        CT.section("desktopSizeOf: \(rows(fx["sizeCases"]).count) stored values")
        var diffs: [String] = []
        for c in rows(fx["sizeCases"]) where DesktopSize.of(c["raw"]).rawValue != c["out"] as! String { diffs.append("\(c["raw"] ?? "nil"): \(DesktopSize.of(c["raw"]).rawValue)") }
        CT.checkRows("every stored size is as the fixture says", diffs)

        CT.section("screenKey: \(rows(fx["screenKeys"]).count) arrangements")
        diffs = []
        for c in rows(fx["screenKeys"]) {
            let got = S.screenKey(S.screens(c["screens"]))
            if got != c["out"] as! String { diffs.append("\(c["name"] as! String): \"\(got)\"") }
        }
        CT.checkRows("every key is as the fixture says, whichever order the screens come in", diffs)
        CT.check("half rounds up, also below zero (not Swift's rounded())", [S.round(2.5), S.round(-2.5), S.round(-0.4), S.round(0.49999)], [3, -2, 0, 0])
        let frame = DesktopRect(x: -2.5, y: 0.5, w: 100.5, h: 50.49)
        CT.check("so a frame is written rounded half up", S.screenKey([DesktopScreen(frame: frame, visible: frame)]), "-2,1,101,50")

        CT.section("isScreenKey: \(rows(fx["isScreenKey"]).count) strings")
        diffs = []
        for c in rows(fx["isScreenKey"]) where S.isScreenKey(c["key"]) != c["out"] as! Bool { diffs.append("\(c["key"] ?? "nil"): \(S.isScreenKey(c["key"]))") }
        CT.checkRows("only what screenKey writes is a key", diffs)
        CT.checkTrue("a number, nothing and a trailing newline are not keys", !S.isScreenKey(7) && !S.isScreenKey(nil) && !S.isScreenKey("0,0,100,100\n") && !S.isScreenKey("٠,0,100,100"))

        CT.section("clampSpot: \(rows(fx["clamps"]).count) spots")
        diffs = []
        for c in rows(fx["clamps"]) {
            let got = S.clampSpot(S.spot(c["spot"]), S.screens(c["screens"]), size: DesktopSize.of(c["size"]))
            let d = CT.diffs(spotJSON(got), c["out"] ?? NSNull())
            if !d.isEmpty { diffs.append("\(c["name"] as! String): \(d.first!)") }
        }
        CT.checkRows("every spot is held where the cat may sit, 24 pt from the head's edge", diffs)

        CT.section("defaultDesktopSpot: \(rows(fx["defaultSpots"]).count) arrangements")
        diffs = []
        for c in rows(fx["defaultSpots"]) {
            let d = CT.diffs(spotJSON(S.defaultSpot(S.screens(c["screens"]), size: DesktopSize.of(c["size"]))), c["out"] ?? NSNull())
            if !d.isEmpty { diffs.append("\(c["name"] as! String): \(d.first!)") }
        }
        CT.checkRows("the first spot is on the main screen, whichever marks it", diffs)

        CT.section("cleanDesktopSpots: \(rows(fx["spotMaps"]).count) stored maps")
        diffs = []
        for c in rows(fx["spotMaps"]) {
            let d = CT.diffs(mapJSON(S.cleanSpots(c["raw"])), c["out"]!)
            if !d.isEmpty { diffs.append("\(c["name"] as! String): \(d.first!)") }
        }
        CT.checkRows("every map is cleaned as the fixture says (text, bad keys, bad spots, the cap of 32)", diffs)

        CT.section("spotFor: \(rows(fx["spotFor"]).count) cases")
        diffs = []
        for c in rows(fx["spotFor"]) {
            let got = S.spotFor(S.cleanSpots(c["spots"]), S.screens(c["screens"]), size: DesktopSize.of(c["size"]))
            let d = CT.diffs(spotJSON(got), c["out"] ?? NSNull())
            if !d.isEmpty { diffs.append("\(c["name"] as! String): \(d.first!)") }
        }
        CT.checkRows("a laptop alone and a laptop with a monitor each keep their own spot", diffs)

        CT.section("rememberSpot: \(rows(fx["remembers"]).count) cases")
        diffs = []
        for c in rows(fx["remembers"]) {
            let got = S.rememberSpot(S.cleanSpots(c["spots"]), S.screens(c["screens"]), S.spot(c["spot"]) ?? DesktopSpot(x: .nan, y: .nan), size: DesktopSize.of(c["size"]))
            let d = CT.diffs(mapJSON(got), c["out"]!)
            if !d.isEmpty { diffs.append("\(c["name"] as! String): \(d.first!)") }
        }
        CT.checkRows("the clamped spot is kept for this arrangement and the others stay; the map keeps 32 and the one just written", diffs)

        CT.section("cleanDesktopSettings: \(rows(fx["settingsCases"]).count) stored blocks")
        let defaults = Cfg.clean(nil)
        CT.checkJSON("the defaults are the fixture's", got: defaults.json, want: fx["settingsDefaults"]!)
        diffs = []
        for c in rows(fx["settingsCases"]) {
            let d = CT.diffs(Cfg.clean(c["raw"]).json, c["out"]!)
            if !d.isEmpty { diffs.append("\(c["name"] as! String): \(d.first!)") }
        }
        CT.checkRows("every block is cleaned as the fixture says (on as text or as the number 1 is off)", diffs)

        CT.section("what the fixture cannot write: numbers that are not numbers, and a cat with nowhere to sit")
        let laptop = S.screens([["frame": ["x": 0, "y": 0, "w": 1512, "h": 982], "visible": ["x": 0, "y": 37, "w": 1512, "h": 875], "main": true]])
        CT.check("one usable screen", laptop.count, 1)
        CT.check("a NaN spot is no spot: it goes to the default", S.clampSpot(DesktopSpot(x: .nan, y: 5), laptop, size: .medium), S.defaultSpot(laptop, size: .medium))
        CT.check("so does infinity", S.clampSpot(DesktopSpot(x: .infinity, y: 5), laptop, size: .medium), S.defaultSpot(laptop, size: .medium))
        CT.check("and a spot past the limit", S.clampSpot(DesktopSpot(x: 200000, y: 5), laptop, size: .medium), S.defaultSpot(laptop, size: .medium))
        CT.check("no screens, no spot", [S.clampSpot(DesktopSpot(x: 5, y: 5), [], size: .medium) == nil, S.defaultSpot([], size: .medium) == nil, S.spotFor([:], [], size: .medium) == nil], [true, true, true])
        CT.check("a screen with a NaN frame is not a screen", S.tidy([DesktopScreen(frame: DesktopRect(x: .nan, y: 0, w: 100, h: 100), visible: DesktopRect(x: 0, y: 0, w: 100, h: 100))]).count, 0)
        CT.check("nor is one with no width", S.tidy([DesktopScreen(frame: DesktopRect(x: 0, y: 0, w: 0.5, h: 100), visible: DesktopRect(x: 0, y: 0, w: 1, h: 1))]).count, 0)
        CT.check("a visible frame that is NaN is the frame", S.tidy([DesktopScreen(frame: DesktopRect(x: 0, y: 0, w: 100, h: 100), visible: DesktopRect(x: .nan, y: 0, w: 100, h: 100))])[0].visible, DesktopRect(x: 0, y: 0, w: 100, h: 100))
        CT.check("twenty screens count as sixteen", S.tidy((0..<20).map { DesktopScreen(frame: DesktopRect(x: Double($0) * 10, y: 0, w: 10, h: 10), visible: DesktopRect(x: Double($0) * 10, y: 0, w: 10, h: 10)) }).count, 16)
        CT.check("a boolean is not a number in a spot", S.spot(["x": true, "y": 1]) == nil, true)
        let tiny = DesktopScreen(frame: DesktopRect(x: 0, y: 0, w: 60, h: 60), visible: DesktopRect(x: 0, y: 0, w: 60, h: 60), main: true)
        CT.check("a screen too small for the cat holds its centre", S.clampSpot(DesktopSpot(x: 1, y: 1), [tiny], size: .large), DesktopSpot(x: 30, y: 30))
        CT.check("a remembered spot over a thousand arrangements stays under 32", S.cleanSpots((0..<1000).reduce(into: [String: Any]()) { $0["\($1),0,100,100"] = ["x": 1, "y": 1] }).count, 32)

        CT.section("the edits: each changes one thing and returns a clean value")
        let base = Cfg.clean(["on": true, "size": "large", "spots": ["0,0,1512,982": ["x": 300, "y": 400]]])
        CT.check("on", base.withOn(false), Cfg(on: false, size: .large, spots: base.spots))
        CT.check("size", base.withSize(.small).size, .small)
        CT.check("remembering a spot", base.remembering(DesktopSpot(x: 5, y: 5), on: laptop).spots, ["0,0,1512,982": DesktopSpot(x: 72, y: 109)])
        CT.check("the spot to use now", base.spot(on: laptop), DesktopSpot(x: 300, y: 400))
        CT.check("the input is never touched", base, Cfg.clean(["on": true, "size": "large", "spots": ["0,0,1512,982": ["x": 300, "y": 400]]]))

        CT.section("the UserDefaults keys, through a dictionary store")
        let store = MemoryBacking()
        CT.check("an empty store loads the defaults", Cfg.load(from: store), Cfg())
        store.values = ["cat.desktop.on": true, "cat.desktop.size": "small", "cat.desktop.spots": "{\"0,0,1512,982\":{\"x\":300,\"y\":400}}", "cat.character": "momo"]
        let loaded = Cfg.load(from: store)
        CT.check("what is stored is loaded (and the other cat keys are not read)", loaded, Cfg(on: true, size: .small, spots: ["0,0,1512,982": DesktopSpot(x: 300, y: 400)]))
        let fresh = MemoryBacking()
        loaded.save(to: fresh)
        CT.check("the keys it writes: the three", fresh.writes, ["cat.desktop.on", "cat.desktop.size", "cat.desktop.spots"])
        CT.check("the switch is a real Bool, the size a word and the spots strict JSON text", [fresh.values["cat.desktop.on"] as? Bool ?? false, fresh.values["cat.desktop.size"] as? String ?? "", fresh.values["cat.desktop.spots"] as? String ?? ""] as [AnyHashable], [true, "small", "{\"0,0,1512,982\":{\"x\":300,\"y\":400}}"] as [AnyHashable])
        CT.check("and loads back as it was", Cfg.load(from: fresh), loaded)
        let before = fresh.writes.count
        loaded.withSize(.large).save(to: fresh, replacing: loaded)
        CT.check("only the key that changed is written", Array(fresh.writes[before...]), ["cat.desktop.size"])
        loaded.save(to: fresh, replacing: loaded)
        CT.check("nothing that did not change is written", fresh.writes.count, before + 1)
        let many = Cfg(spots: ["1,0,100,100": DesktopSpot(x: 2, y: 3), "0,0,100,100": DesktopSpot(x: 1, y: 1)])
        CT.check("the same map is always the same text, keys in order", many.spotsText, "{\"0,0,100,100\":{\"x\":1,\"y\":1},\"1,0,100,100\":{\"x\":2,\"y\":3}}")

        CT.section("a store that is wrong in every way still loads")
        let wild = MemoryBacking()
        wild.values = ["cat.desktop.on": 1, "cat.desktop.size": 96, "cat.desktop.spots": Data("x".utf8)]
        CT.check("a number for on, a number for the size and data for the spots: the defaults", Cfg.load(from: wild), Cfg())
        wild.values = ["cat.desktop.on": "true", "cat.desktop.size": "Large", "cat.desktop.spots": "{\"0,0,100,100\":"]
        CT.check("text for on, a size in the wrong case and cut-off JSON: the defaults", Cfg.load(from: wild), Cfg())
        wild.values = ["cat.desktop.spots": "{\"0,0,100,100\":{\"x\":1,\"y\":2},}"]
        CT.check("JSON with a comma before the closing brace is not JSON", Cfg.load(from: wild).spots, [:])
        CT.finish()
    }
}
