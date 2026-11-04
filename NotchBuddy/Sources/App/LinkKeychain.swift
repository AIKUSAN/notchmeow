import CryptoKit
import Foundation
import Security

// The link's secrets (sub-project G2): this machine's static private key, its device id, and one item for each machine it has paired. They live in the Keychain and nowhere else: never in a
// file, a default, a log or a fixture (docs/LINK-CONTRACT.md "Notes for ports"). The three account names are frozen like the pill IDs:
//   `link.static-key`   32 bytes, the Curve25519 private key of the Noise handshakes
//   `link.device-id`    16 bytes, this machine's random device id (not a secret, but it must survive with the key)
//   `link.peer.<id>`    one JSON object {name, key, at} for each paired machine, <id> being its 32 lower-case hex digits
// `LinkKeychain` takes the store it reads and writes, so the tests run it on a memory store and, under a test-only service name, on the real Keychain.

/// What a store says about one item: there, not there, or not readable. Only `.absent` may lead to a new secret being made.
enum LinkSecretLookup: Equatable { case absent, found(Data), failed }

protocol LinkSecretStore: Sendable {
    func get(_ account: String) -> Data?
    /// Tells "not there" apart from "could not be read" (a locked Keychain, a refused prompt): `get` cannot.
    func lookup(_ account: String) -> LinkSecretLookup
    /// False when the item could not be written; an existing item is then left as it was.
    func set(_ account: String, _ data: Data) -> Bool
    /// Adds only: false when an item is already there (it is left as it was, never replaced) or when it could not be written. The first use of a secret goes through here.
    func create(_ account: String, _ data: Data) -> Bool
    func remove(_ account: String)
    /// Every account whose name starts with `prefix`.
    func accounts(prefix: String) -> [String]
}

extension LinkSecretStore {
    func lookup(_ account: String) -> LinkSecretLookup {
        get(account).map { .found($0) } ?? .absent
    }
}

/// The system Keychain, as a generic password under `service`. The strictest access the app already uses for its keys (`Keychain` in ClaudeService.swift): only while the Mac is unlocked, never synced
/// to iCloud, never migrated to another device.
struct SystemSecretStore: LinkSecretStore {
    /// The app's Keychain service name: the value of `Keychain.service` in ClaudeService.swift (scripts/test-link-wiring.sh pins that the two are the same text). **A Debug build keeps everything of
    /// the link under a service name of its own** (the owner's rule, 2026-10-15), chosen at compile time, so a Debug build, its fake peer and its tests can never write under the real name.
    /// Release and App Store builds (and the test programs, which are not built with DEBUG) use the normal one. `scripts/check-app-binary.sh` proves the debug string is absent from them.
    #if DEBUG && !APPSTORE
    static let appService = "io.github.aikusan.notchmeow.debug"
    #else
    static let appService = "io.github.aikusan.notchmeow"
    #endif
    let service: String
    init(service: String = SystemSecretStore.appService) { self.service = service }

    private func base(_ account: String?) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        if let account { q[kSecAttrAccount as String] = account }
        return q
    }

    func get(_ account: String) -> Data? {
        if case .found(let data) = lookup(account) { return data }
        return nil
    }

    func lookup(_ account: String) -> LinkSecretLookup {
        var q = base(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return .absent }
        guard status == errSecSuccess, let data = out as? Data else { return .failed }
        return .found(data)
    }

    /// Adds the item; when one is already there, replaces its value instead. Never deletes first: a failed write leaves the old item.
    func set(_ account: String, _ data: Data) -> Bool {
        if create(account, data) { return true }
        let update: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: accessible]
        return SecItemUpdate(base(account) as CFDictionary, update as CFDictionary) == errSecSuccess
    }

    /// Adds the item only. A duplicate is not updated: the item already there is kept.
    func create(_ account: String, _ data: Data) -> Bool {
        var item = base(account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = accessible
        item[kSecAttrSynchronizable as String] = kCFBooleanFalse!
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    private var accessible: String { kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String }

    func remove(_ account: String) { SecItemDelete(base(account) as CFDictionary) }

    func accounts(prefix: String) -> [String] {
        var q = base(nil)
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitAll
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let rows = out as? [[String: Any]] else { return [] }
        return rows.compactMap { $0[kSecAttrAccount as String] as? String }.filter { $0.hasPrefix(prefix) }
    }
}

/// A store in memory, for the tests and for the Debug fake peer: nothing here touches the Keychain.
final class MemorySecretStore: LinkSecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]
    var failWrites = false
    var failReads = false
    func get(_ account: String) -> Data? { lock.withLock { failReads ? nil : items[account] } }
    func lookup(_ account: String) -> LinkSecretLookup {
        lock.withLock { failReads ? .failed : items[account].map { .found($0) } ?? .absent }
    }
    func set(_ account: String, _ data: Data) -> Bool { lock.withLock { if failWrites { return false }; items[account] = data; return true } }
    func create(_ account: String, _ data: Data) -> Bool {
        lock.withLock { if failWrites || items[account] != nil { return false }; items[account] = data; return true }
    }
    func remove(_ account: String) { lock.withLock { _ = items.removeValue(forKey: account) } }
    func accounts(prefix: String) -> [String] { lock.withLock { items.keys.filter { $0.hasPrefix(prefix) }.sorted() } }
}

/// A machine this one has paired.
struct LinkPeer: Equatable, Sendable {
    let id: String      // 32 lower-case hex digits, not all zero
    let name: String    // the authenticated name from its hello
    let key: String     // its static public key, 64 lower-case hex digits
    let at: Int         // when it was paired (seconds since 1970; shown in Devices, never decides anything)
}

enum LinkKeychainError: Error, Equatable {
    case corrupt          // an item exists and is not what it should be: never replaced silently (the old key may still be wanted)
    case readFailed       // an item may exist but could not be read: nothing is generated, written or replaced
    case writeFailed
    case invalidPeer      // not canonical, the zero id, or this machine's own id
    case idKeyMismatch    // the id is already paired under another key: forget it first
}

struct LinkKeychain: Sendable {
    static let staticKeyAccount = "link.static-key"
    static let deviceIdAccount = "link.device-id"
    static let peerPrefix = "link.peer."

    let store: any LinkSecretStore
    init(store: any LinkSecretStore = SystemSecretStore()) { self.store = store }

    // MARK: This machine

    /// The static private key; made on first use (32 random bytes from CryptoKit) and written at once. The first write only adds: a racing call's key is kept and read back, never replaced.
    func staticKey() throws -> Curve25519.KeyAgreement.PrivateKey {
        if case .absent = store.lookup(Self.staticKeyAccount) {
            _ = store.create(Self.staticKeyAccount, Curve25519.KeyAgreement.PrivateKey().rawRepresentation)
        }
        switch store.lookup(Self.staticKeyAccount) {
        case .found(let raw):
            guard raw.count == 32, let k = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw) else { throw LinkKeychainError.corrupt }
            return k
        case .failed:
            throw LinkKeychainError.readFailed
        case .absent:
            throw LinkKeychainError.writeFailed
        }
    }

    func staticPublicHex() throws -> String { LinkBytes.hex(try staticKey().publicKey.rawRepresentation) }

    /// This machine's device id (32 lower-case hex digits, never all zero); made on first use, add-only like `staticKey()`: a racing call's id is kept and read back.
    func deviceId() throws -> String {
        if case .absent = store.lookup(Self.deviceIdAccount) {
            var id: Data
            repeat { id = Data((0..<LinkWire.idLen).map { _ in UInt8.random(in: 0...255) }) } while id.allSatisfy { $0 == 0 }
            _ = store.create(Self.deviceIdAccount, id)
        }
        switch store.lookup(Self.deviceIdAccount) {
        case .found(let raw):
            let id = LinkBytes.hex(raw)
            guard raw.count == LinkWire.idLen, id != LinkBytes.zeroId else { throw LinkKeychainError.corrupt }
            return id
        case .failed:
            throw LinkKeychainError.readFailed
        case .absent:
            throw LinkKeychainError.writeFailed
        }
    }

    // MARK: Paired machines

    private struct Stored: Codable { let name: String; let key: String; let at: Int }

    /// Every paired machine that reads back clean. An item that does not (a wrong account name, a key that is not 64 lower-case hex digits, a name the card would refuse) is skipped, not
    /// deleted, and not trusted.
    func peers() -> [String: LinkPeer] {
        var out: [String: LinkPeer] = [:]
        for account in store.accounts(prefix: Self.peerPrefix) {
            let id = String(account.dropFirst(Self.peerPrefix.count))
            guard LinkBytes.isIdHex(id), id != LinkBytes.zeroId, let raw = store.get(account), let s = try? JSONDecoder().decode(Stored.self, from: raw),
                  LinkBytes.isHex32(s.key), (try? LinkWire.deviceName(Array(s.name.utf8))) != nil else { continue }
            out[id] = LinkPeer(id: id, name: s.name, key: s.key, at: s.at)
        }
        return out
    }

    /// The paired map the pairing machines take: device id to static key, lower-case hex.
    func pairedKeys() -> [String: String] { peers().mapValues(\.key) }

    func peer(_ id: String) -> LinkPeer? { peers()[id] }

    /// Stores a machine after a pairing both users confirmed. The paired map is read **again here**, not taken from the snapshot the pairing started with: two pairings can overlap for up to two
    /// minutes (docs/LINK-CONTRACT.md). Re-pairing the same id under the same key refreshes the name.
    func add(_ p: LinkPeer, ownId: String) throws {
        guard LinkBytes.isIdHex(p.id), p.id != LinkBytes.zeroId, p.id != ownId, LinkBytes.isHex32(p.key), (try? LinkWire.deviceName(Array(p.name.utf8))) != nil else { throw LinkKeychainError.invalidPeer }
        if let existing = peer(p.id) {
            if existing.key != p.key { throw LinkKeychainError.idKeyMismatch }
        } else if store.lookup(Self.peerPrefix + p.id) != .absent {
            throw LinkKeychainError.corrupt   // an unreadable or unclean item under this id is never overwritten
        }
        let data = try JSONEncoder().encode(Stored(name: p.name, key: p.key, at: p.at))
        guard store.set(Self.peerPrefix + p.id, data) else { throw LinkKeychainError.writeFailed }
    }

    func forget(_ id: String) {
        guard LinkBytes.isIdHex(id) else { return }
        store.remove(Self.peerPrefix + id)
    }
}
