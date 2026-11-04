import Foundation

// What the link saves and how it is cleaned (sub-project G2): whether this Mac is visible on the network, and the name the other machines show for it. Two keys in UserDefaults:
// `link.visible` (a Bool, **off until the user turns it on** in Settings → Devices: until then there is no listener, no advert and no local-network prompt) and `link.deviceName` (text).
// The keys are frozen like the cat settings' keys. Secrets are not here: the keys and the paired machines are in the Keychain (LinkKeychain). Foundation only.

protocol LinkSettingsBacking {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: LinkSettingsBacking {}

struct LinkSettings: Equatable, Sendable {
    var visible = false
    var deviceName: String

    enum Key {
        static let visible = "link.visible", deviceName = "link.deviceName"
    }

    /// `true` only for the boolean true: the number 1 and the text "true" are off (a preferences file can be hand-edited).
    static func isTrue(_ v: Any?) -> Bool {
        guard let n = v as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return false }
        return n.boolValue
    }

    /// A name that the other machine's card would accept (`LinkWire.deviceName`: 1 to 63 bytes, no control, format or invisible character, no space at either end), or nil.
    static func validName(_ v: Any?) -> String? {
        guard let s = v as? String, (try? LinkWire.deviceName(Array(s.utf8))) != nil else { return nil }
        return s
    }

    /// The name offered by default, from the Mac's own name ("Sam's MacBook Pro"): the characters a card would refuse are dropped, the ends trimmed, the rest cut to 63 bytes at a
    /// character. A name with nothing left is "Mac".
    static func defaultName(host: String) -> String {
        var kept: [Unicode.Scalar] = []
        for s in host.unicodeScalars where !LinkName.isBadCategory(s) && !LinkName.isInvisible(s) { kept.append(s) }
        while let f = kept.first, LinkName.isSpace(f) { kept.removeFirst() }
        while let l = kept.last, LinkName.isSpace(l) { kept.removeLast() }
        var out: [Unicode.Scalar] = [], bytes = 0
        for s in kept { if bytes + UTF8.width(s) > LinkWire.deviceNameMax { break }; out.append(s); bytes += UTF8.width(s) }
        while let l = out.last, LinkName.isSpace(l) { out.removeLast() }
        return out.isEmpty ? "Mac" : LinkName.string(out)
    }

    /// Everything stored, cleaned: visible only when exactly `true`, the name when it passes `validName`, else the default from `host`. Never throws.
    static func clean(visible: Any?, deviceName: Any?, host: String) -> LinkSettings {
        LinkSettings(visible: isTrue(visible), deviceName: validName(deviceName) ?? defaultName(host: host))
    }

    static func load(from store: any LinkSettingsBacking, host: String) -> LinkSettings {
        clean(visible: store.object(forKey: Key.visible), deviceName: store.object(forKey: Key.deviceName), host: host)
    }

    func save(to store: any LinkSettingsBacking) {
        store.set(visible, forKey: Key.visible)
        store.set(deviceName, forKey: Key.deviceName)
    }
}

/// What Settings → Devices lists and what the Send menu offers: the machines seen on the network and the machines paired, merged. Pure, so the order and the states are tested.
enum LinkDirectory {
    struct Row: Equatable, Sendable {
        enum State: Equatable, Sendable {
            case pairedOnline       // paired, and its advert is on the network now
            case pairedOffline      // paired, not seen
            case available          // seen, not paired
        }
        let id: String
        let name: String
        let state: State
    }

    /// Paired machines that are online first (a paired machine's name is the authenticated one it gave when it paired, not the advert's), then the paired that are not, then the machines only
    /// seen, each group by name. An advert with this machine's own id is never listed (`LinkWire.parseTxt` refuses it already; this is the second line).
    static func rows(adverts: [LinkWire.Advert], peers: [String: LinkPeer], ownId: String) -> [Row] {
        let seen = Dictionary(adverts.filter { $0.id != ownId }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func byName(_ a: Row, _ b: Row) -> Bool { a.name.localizedStandardCompare(b.name) == .orderedAscending }
        let paired = peers.values.map { Row(id: $0.id, name: $0.name, state: seen[$0.id] != nil ? .pairedOnline : .pairedOffline) }
        let online = paired.filter { $0.state == .pairedOnline }.sorted(by: byName), offline = paired.filter { $0.state == .pairedOffline }.sorted(by: byName)
        let others = seen.values.filter { peers[$0.id] == nil }.map { Row(id: $0.id, name: $0.name, state: .available) }.sorted(by: byName)
        return online + offline + others
    }
}
