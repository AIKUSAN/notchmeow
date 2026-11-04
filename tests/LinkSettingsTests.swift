import Foundation

// LinkSettings (what is saved and how it is cleaned) and LinkDirectory (what Devices and the Send menu list). No UserDefaults, no Keychain: a dictionary stands in for the store.
// Run it through scripts/test-link-settings.sh.

final class DictBacking: LinkSettingsBacking {
    var values: [String: Any] = [:]
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
}

@main
enum LinkSettingsTests {
    @MainActor static func main() {
        CT.section("a Mac that has stored nothing")
        let fresh = LinkSettings.load(from: DictBacking(), host: "Sam's MacBook Pro")
        CT.check("is not visible on the network, and offers its own name", [fresh.visible ? 1 : 0, fresh.deviceName == "Sam's MacBook Pro" ? 1 : 0], [0, 1])

        CT.section("what is stored is cleaned")
        func load(_ visible: Any?, _ name: Any?) -> LinkSettings { LinkSettings.clean(visible: visible, deviceName: name, host: "Studio") }
        CT.check("only the boolean true is visible: 1, \"true\", 1.0, null and a list are not", [load(true, nil).visible, load(1, nil).visible, load("true", nil).visible, load(NSNull(), nil).visible, load([true], nil).visible, load(false, nil).visible], [true, false, false, false, false, false])
        CT.check("a good name is kept", load(nil, "Desk PC").deviceName, "Desk PC")
        CT.check("a name the card would refuse falls back to the default: empty, padded, 64 bytes, a zero-width space, a newline, a number", [load(nil, "").deviceName, load(nil, " x").deviceName, load(nil, String(repeating: "n", count: 64)).deviceName, load(nil, "a\u{200B}b").deviceName, load(nil, "a\nb").deviceName, load(nil, 5).deviceName], Array(repeating: "Studio", count: 6))

        CT.section("the default name")
        CT.check("controls and invisible characters are dropped, the ends trimmed", LinkSettings.defaultName(host: "  Sam\u{200B}'s\tMac \n"), "Sam'sMac")
        CT.check("a long name is cut at a character, to 63 bytes", [LinkSettings.defaultName(host: String(repeating: "\u{1F408}", count: 30)).utf8.count, LinkSettings.defaultName(host: String(repeating: "a", count: 100)).utf8.count], [60, 63])
        CT.check("nothing left is Mac", [LinkSettings.defaultName(host: ""), LinkSettings.defaultName(host: " \u{200B}\n")], ["Mac", "Mac"])

        CT.section("save and load")
        let store = DictBacking()
        LinkSettings(visible: true, deviceName: "Desk PC").save(to: store)
        CT.check("what is saved is read back", LinkSettings.load(from: store, host: "x"), LinkSettings(visible: true, deviceName: "Desk PC"))
        CT.check("under the frozen keys", [store.values["link.visible"] as? Bool, store.values["link.deviceName"] as? String] as [AnyHashable?], [true, "Desk PC"] as [AnyHashable?])

        CT.section("the directory")
        let own = String(repeating: "d1", count: 16)
        func id(_ n: UInt8) -> String { String(repeating: String(format: "%02x", n), count: 16) }
        func peer(_ n: UInt8, _ name: String) -> LinkPeer { LinkPeer(id: id(n), name: name, key: String(repeating: "c1", count: 32), at: 1) }
        let adverts = [LinkWire.Advert(id: id(1), name: "zed's PC"), LinkWire.Advert(id: id(2), name: "Laptop (advert name)"), LinkWire.Advert(id: id(3), name: "Bar"), LinkWire.Advert(id: own, name: "This Mac"), LinkWire.Advert(id: id(3), name: "Bar again")]
        let peers = [id(1): peer(1, "Zed PC"), id(2): peer(2, "Alpha Laptop"), id(9): peer(9, "Old Phone")]
        let rows = LinkDirectory.rows(adverts: adverts, peers: peers, ownId: own)
        CT.check("paired online by name, then paired offline, then only seen; the advert's name never replaces a paired name; this Mac is not listed; a repeated advert counts once",
                 rows.map { "\($0.name)|\($0.state)" }, ["Alpha Laptop|pairedOnline", "Zed PC|pairedOnline", "Old Phone|pairedOffline", "Bar|available"])
        CT.check("nothing seen, nothing paired: no rows", LinkDirectory.rows(adverts: [], peers: [:], ownId: own), [])
        CT.finish()
    }
}
