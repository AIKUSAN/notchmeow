import Foundation

// The dismissal memory and the stored settings against tests/fixtures/sidekick/dismiss-cases.json and settings-cases.json, and what the fixture cannot write: the UserDefaults keys, what a
// hand-edited preferences file loads as, and that a save writes only what changed. Run through scripts/test-sidekick-settings.sh.

@main
enum SidekickSettingsTests {
    typealias S = SidekickSettings
    static func rows(_ x: Any?) -> [[String: Any]] { x as! [[String: Any]] }

    @MainActor static func main() {
        let dx = CT.fixture("dismiss-cases.json", dir: "sidekick"), sx = CT.fixture("settings-cases.json", dir: "sidekick")

        CT.section("the frozen kinds")
        CT.check("the five kinds, in order", S.kinds, dx["kinds"] as! [String])
        CT.check("two dismissals mute a kind", S.muteAt, (dx["muteAt"] as! NSNumber).intValue)
        CT.check("the same kinds in the settings fixture", S.kinds, sx["kinds"] as! [String])

        let cases = rows(dx["cases"])
        CT.section("dismiss, unmute and muted: \(cases.count) cases, the state and the muted kinds after every step")
        var diffs: [String] = []
        for c in cases {
            var s = SidekickSettings(on: true, local: true, dismissals: S.cleanDismissals(c["start"]))
            for (i, op) in rows(c["ops"]).enumerated() {
                let kind = op["kind"] as? String ?? "\u{0}"   // a kind that is not text is no kind
                switch op["op"] as! String {
                case "dismiss": s = s.dismissed(kind)
                case "unmute": s = s.unmuted(kind)
                case "mute": s = s.muting(kind)
                default: diffs.append("\(c["name"] as! String) step \(i): unknown op")
                }
                let want = rows(c["trail"])[i]
                let d = CT.diffs(s.dismissals, want["state"]!) + CT.diffs(s.mutedKinds, want["muted"]!)
                if !d.isEmpty { diffs.append("\(c["name"] as! String) step \(i): \(d.first!)") }
            }
        }
        CT.checkRows("every step is the fixture's", diffs)

        let cleans = rows(sx["cases"])
        CT.section("SidekickSettings.clean: \(cleans.count) stored values, the clean value each one becomes")
        diffs = []
        for c in cleans {
            let got = S.clean(c["raw"])
            let d = CT.diffs(got.json, c["clean"]!)
            if !d.isEmpty { diffs.append("\(c["name"] as! String): \(d.first!)") }
            if S.clean(got.json) != got { diffs.append("\(c["name"] as! String): cleaning twice is not cleaning once") }
        }
        CT.checkRows("every raw value cleans to the fixture's, and cleaning twice is cleaning once", diffs)

        CT.check("a count that is not finite is 0", [S.cleanCount(Double.nan), S.cleanCount(Double.infinity), S.cleanCount(-Double.infinity)], [0, 0, 0])

        CT.section("the UserDefaults keys")
        CT.check("the three keys", [S.Key.on, S.Key.local, S.Key.dismissals], ["sidekick.on", "sidekick.local", "sidekick.dismissals"])
        let mem = MemoryBacking()
        CT.check("nothing stored: everything on, nothing dismissed", S.load(from: mem), SidekickSettings())
        let muted = SidekickSettings().dismissed("recap").dismissed("recap").dismissed("stuck.loop").withOn(false)
        muted.save(to: mem)
        CT.check("a first save writes the three keys", mem.writes, [S.Key.on, S.Key.local, S.Key.dismissals])
        CT.check("the dismissals are stored as sorted JSON text", mem.values[S.Key.dismissals] as? String, #"{"recap":2,"stuck.errors":0,"stuck.loop":1,"stuck.silent":0,"stuck.waiting":0}"#)
        CT.check("and load back the same", S.load(from: mem), muted)
        let before = mem.writes.count
        muted.unmuted("recap").save(to: mem, replacing: muted)
        CT.check("a save writes only what changed", Array(mem.writes.dropFirst(before)), [S.Key.dismissals])
        let hand = MemoryBacking()
        hand.values = [S.Key.on: "false", S.Key.local: 0, S.Key.dismissals: "{not json"]
        CT.check("a hand-edited store loads as the defaults, never a throw", S.load(from: hand), SidekickSettings())
        hand.values[S.Key.on] = false
        hand.values[S.Key.dismissals] = #"{"recap":5,"stuck.silent":-1,"bogus":2}"#
        CT.check("a switch that is the boolean false is off, a count above 2 is 2, a bad count and an unknown kind go", S.load(from: hand), SidekickSettings(on: false, local: true, dismissals: ["recap": 2, "stuck.loop": 0, "stuck.errors": 0, "stuck.waiting": 0, "stuck.silent": 0]))
        CT.check("an unknown kind changes nothing", SidekickSettings().dismissed("stuck.sleepy").unmuted("constructor"), SidekickSettings())

        CT.section("the store: the app's one holder")
        let backing = MemoryBacking()
        let store = SidekickStore(backing: backing)
        CT.check("it starts from what is stored: the defaults", store.settings, SidekickSettings())
        store.setOn(false)
        store.setLocal(false)
        CT.check("the two switches are saved", [backing.values[S.Key.on] as? Bool, backing.values[S.Key.local] as? Bool], [false, false])
        store.dismiss("recap"); store.dismiss("recap"); store.dismiss("stuck.silent")
        CT.check("two dismissals mute a kind, one does not", store.settings.mutedKinds, ["recap"])
        CT.check("and they are saved as text", backing.values[S.Key.dismissals] as? String, #"{"recap":2,"stuck.errors":0,"stuck.loop":0,"stuck.silent":1,"stuck.waiting":0}"#)
        let writes = backing.writes.count
        store.setOn(false)
        store.dismiss("nonsense")
        CT.check("a change that changes nothing writes nothing", backing.writes.count, writes)
        store.unmute("recap")
        CT.check("Unmute sets a kind back to zero", store.settings.mutedKinds, [])
        CT.check("a second store on the same backing sees it all", SidekickStore(backing: backing).settings, store.settings)
        CT.finish()
    }
}
