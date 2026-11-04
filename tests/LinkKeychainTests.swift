import CryptoKit
import Foundation

// LinkKeychain: the three kinds of item, the checks at store time, and a round trip through the real Keychain under a service name that exists only for this test (and is deleted again).
// Run it through scripts/test-link-keychain.sh. NM_SKIP_REAL_KEYCHAIN=1 skips the part that touches the Keychain.

@main
enum LinkKeychainTests {
    static let peerKey = String(repeating: "c1", count: 32)
    static let peerId = String(repeating: "e1", count: 16)
    static let ownId = String(repeating: "d1", count: 16)
    static func peer(_ id: String = peerId, key: String = peerKey, name: String = "Studio PC") -> LinkPeer { LinkPeer(id: id, name: name, key: key, at: 1_760_000_000) }

    static func thrown(_ f: () throws -> Void) -> LinkKeychainError? {
        do { try f(); return nil } catch { return error as? LinkKeychainError }
    }

    @MainActor static func suite(_ label: String, _ store: any LinkSecretStore) {
        let kc = LinkKeychain(store: store)
        CT.section("\(label): this machine's key and id")
        let k1 = try! kc.staticKey(), k2 = try! kc.staticKey()
        CT.check("the static key is made once and read back, 32 bytes", [k1.rawRepresentation == k2.rawRepresentation, k1.rawRepresentation.count == 32], [true, true])
        CT.check("its public half is 64 lower-case hex digits", LinkBytes.isHex32(try! kc.staticPublicHex()), true)
        let id = try! kc.deviceId()
        CT.check("the device id is 32 lower-case hex digits, not zero, and stays", [LinkBytes.isIdHex(id), id != LinkBytes.zeroId, (try! kc.deviceId()) == id], [true, true, true])

        CT.section("\(label): paired machines")
        CT.check("nothing paired at first", kc.peers().count, 0)
        try! kc.add(peer(), ownId: ownId)
        CT.check("a stored machine reads back as it was", kc.peers(), [peerId: peer()])
        CT.check("the paired map is id to key", kc.pairedKeys(), [peerId: peerKey])
        try! kc.add(peer(name: "Studio PC 2"), ownId: ownId)
        CT.check("the same id under the same key refreshes the name", kc.peer(peerId)?.name, "Studio PC 2")
        CT.check("the same id under another key is refused, and the stored key stays", [thrown { try kc.add(peer(key: String(repeating: "f1", count: 32)), ownId: ownId) }, kc.peer(peerId)?.key == peerKey] as [AnyHashable?], [LinkKeychainError.idKeyMismatch, true] as [AnyHashable?])
        CT.check("this machine's own id, the zero id, a capital id and a short key are refused", [
            thrown { try kc.add(peer(ownId), ownId: ownId) }, thrown { try kc.add(peer(LinkBytes.zeroId), ownId: ownId) },
            thrown { try kc.add(peer(String(repeating: "E1", count: 16)), ownId: ownId) }, thrown { try kc.add(peer(key: "c1c1"), ownId: ownId) },
            thrown { try kc.add(peer(name: " padded"), ownId: ownId) },
        ], [.invalidPeer, .invalidPeer, .invalidPeer, .invalidPeer, .invalidPeer])
        CT.check("a second machine is a second item", { try! kc.add(peer(String(repeating: "e2", count: 16), key: String(repeating: "c2", count: 32), name: "Laptop"), ownId: ownId); return kc.peers().count }(), 2)
        // An item that does not read back clean is skipped, never trusted and never deleted.
        _ = store.set(LinkKeychain.peerPrefix + String(repeating: "E3", count: 16), Data("{}".utf8))
        _ = store.set(LinkKeychain.peerPrefix + String(repeating: "e4", count: 16), Data("not json".utf8))
        _ = store.set(LinkKeychain.peerPrefix + String(repeating: "e5", count: 16), Data("{\"name\":\"x\",\"key\":\"c1\",\"at\":1}".utf8))
        CT.check("a bad item is skipped and left in place", [kc.peers().count, store.accounts(prefix: LinkKeychain.peerPrefix).count], [2, 5])
        kc.forget(peerId)
        CT.check("Forget removes one machine and nothing else", [kc.peer(peerId) == nil ? 0 : 1, kc.peers().count], [0, 1])
        kc.forget("not an id")
        CT.check("Forget with something that is not an id does nothing", kc.peers().count, 1)

        CT.section("\(label): damaged secrets are never replaced")
        _ = store.set(LinkKeychain.staticKeyAccount, Data(count: 5))
        CT.check("a key item of the wrong size is corrupt", thrown { _ = try kc.staticKey() }, .corrupt)
        CT.check("and is still there", store.get(LinkKeychain.staticKeyAccount)?.count, 5)
        _ = store.set(LinkKeychain.deviceIdAccount, Data(count: 16))
        CT.check("an all-zero device id is corrupt", thrown { _ = try kc.deviceId() }, .corrupt)

        CT.section("\(label): lookups and writes over an item")
        CT.check("a missing item reads as absent", store.lookup("link.probe.absent"), .absent)
        let probe = "link.probe.replace"
        let writes = [store.set(probe, Data("one".utf8)), store.set(probe, Data("two".utf8)), store.set(probe, Data("three".utf8))]
        CT.check("a write over an existing item replaces it, and the next write works too", [writes.allSatisfy { $0 }, store.get(probe) == Data("three".utf8)], [true, true])
        let added = "link.probe.add-only"
        CT.check("an add-only create on a missing item works", store.create(added, Data("first".utf8)), true)
        CT.check("an add-only create over an item is refused and does not replace it", [store.create(added, Data("second".utf8)), store.get(added) == Data("first".utf8)], [false, true])
    }

    /// A memory store in which another writer gets in first: the first write to `account`, a create or a set, is preceded by `racer`'s value, as a racing call would leave it.
    final class RacingStore: LinkSecretStore, @unchecked Sendable {
        let inner = MemorySecretStore()
        let account: String
        let racer: Data
        private let lock = NSLock()
        private var raced = false
        init(account: String, racer: Data) { self.account = account; self.racer = racer }
        private func race(_ account: String) {
            guard account == self.account else { return }
            lock.withLock { if !raced { raced = true; _ = inner.set(account, racer) } }
        }
        func get(_ account: String) -> Data? { inner.get(account) }
        func lookup(_ account: String) -> LinkSecretLookup { inner.lookup(account) }
        func set(_ account: String, _ data: Data) -> Bool { race(account); return inner.set(account, data) }
        func create(_ account: String, _ data: Data) -> Bool { race(account); return inner.create(account, data) }
        func remove(_ account: String) { inner.remove(account) }
        func accounts(prefix: String) -> [String] { inner.accounts(prefix: prefix) }
    }

    @MainActor static func main() {
        suite("memory", MemorySecretStore())

        CT.section("a racing writer on the first use: its value is kept, never replaced")
        let racedKey = RacingStore(account: LinkKeychain.staticKeyAccount, racer: Curve25519.KeyAgreement.PrivateKey().rawRepresentation)
        CT.check("the static key another writer made first is the one returned", try! LinkKeychain(store: racedKey).staticKey().rawRepresentation, racedKey.racer)
        CT.check("and the item still holds that writer's value", racedKey.inner.get(LinkKeychain.staticKeyAccount), racedKey.racer)
        let racedId = RacingStore(account: LinkKeychain.deviceIdAccount, racer: Data(repeating: 0x7a, count: 16))
        CT.check("the device id another writer made first is the one returned", try! LinkKeychain(store: racedId).deviceId(), LinkBytes.hex(racedId.racer))
        CT.check("and the item still holds that writer's id", racedId.inner.get(LinkKeychain.deviceIdAccount), racedId.racer)
        let racedBad = RacingStore(account: LinkKeychain.staticKeyAccount, racer: Data(count: 5))
        CT.check("a racing writer's unclean key is corrupt, and left in place", thrown { _ = try LinkKeychain(store: racedBad).staticKey() }, .corrupt)
        CT.check("and the item still holds it", racedBad.inner.get(LinkKeychain.staticKeyAccount)?.count, 5)

        let memory = MemorySecretStore(); memory.failWrites = true
        CT.section("a write that fails")
        CT.check("is reported, never swallowed", [thrown { _ = try LinkKeychain(store: memory).staticKey() }, thrown { _ = try LinkKeychain(store: memory).deviceId() }, thrown { try LinkKeychain(store: memory).add(peer(), ownId: ownId) }], [.writeFailed, .writeFailed, .writeFailed])
        let renamed = MemorySecretStore(); let renamedKc = LinkKeychain(store: renamed)
        try! renamedKc.add(peer(), ownId: ownId)
        renamed.failWrites = true
        CT.check("a failed write over a machine already stored is reported", thrown { try renamedKc.add(peer(name: "Renamed"), ownId: ownId) }, .writeFailed)
        CT.check("and the old name stays", renamedKc.peer(peerId)?.name, "Studio PC")

        CT.section("a read that fails: never generated, never written, never replaced")
        let unread = MemorySecretStore(); unread.failReads = true
        CT.check("the static key throws readFailed", thrown { _ = try LinkKeychain(store: unread).staticKey() }, .readFailed)
        CT.check("the device id throws readFailed", thrown { _ = try LinkKeychain(store: unread).deviceId() }, .readFailed)
        CT.check("adding a machine throws corrupt", thrown { try LinkKeychain(store: unread).add(peer(), ownId: ownId) }, .corrupt)
        CT.check("and nothing was written", unread.accounts(prefix: "").count, 0)
        let seeded = MemorySecretStore(); let seededKc = LinkKeychain(store: seeded)
        let seededKey = try! seededKc.staticKey().rawRepresentation
        let seededId = try! seededKc.deviceId()
        seeded.failReads = true
        CT.check("with both items stored, an unreadable key still throws readFailed", thrown { _ = try seededKc.staticKey() }, .readFailed)
        CT.check("and an unreadable id too", thrown { _ = try seededKc.deviceId() }, .readFailed)
        seeded.failReads = false
        CT.check("the stored key is the same afterwards", seeded.get(LinkKeychain.staticKeyAccount), seededKey)
        CT.check("the stored id is the same afterwards", seeded.get(LinkKeychain.deviceIdAccount).map { LinkBytes.hex($0) }, seededId)
        CT.check("and the key reads back once reads work again", try! seededKc.staticKey().rawRepresentation, seededKey)
        let blocked = MemorySecretStore(); let blockedKc = LinkKeychain(store: blocked)
        let blockedId = String(repeating: "e6", count: 16)
        _ = blocked.set(LinkKeychain.peerPrefix + blockedId, Data("not json".utf8))
        CT.check("a machine whose id holds an unclean item is refused as corrupt", thrown { try blockedKc.add(peer(blockedId), ownId: ownId) }, .corrupt)
        CT.check("and that item is left in place", blocked.get(LinkKeychain.peerPrefix + blockedId), Data("not json".utf8))

        if ProcessInfo.processInfo.environment["NM_SKIP_REAL_KEYCHAIN"] == "1" {
            print("real Keychain: skipped (NM_SKIP_REAL_KEYCHAIN=1)")
        } else {
            // The script picks the name and checks from outside afterwards that nothing is left under it; a run of the program alone makes its own.
            let service = ProcessInfo.processInfo.environment["NM_LINK_TEST_SERVICE"] ?? "io.github.aikusan.notchmeow.test.link.\(UUID().uuidString)"
            let real = SystemSecretStore(service: service)
            CT.checkTrue("the test service name is neither the app's, nor the Debug build's, nor the normal one", service != SystemSecretStore.appService && service != "io.github.aikusan.notchmeow" && service != "io.github.aikusan.notchmeow.debug" && service.contains(".test."))
            suite("real Keychain", real)
            // Delete everything this run made, whatever the checks said.
            for a in real.accounts(prefix: "") { real.remove(a) }
            CT.check("the real Keychain holds nothing of the test any more", real.accounts(prefix: ""), [])
        }
        CT.finish()
    }
}
