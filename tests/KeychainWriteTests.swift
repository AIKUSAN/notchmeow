import Foundation
import Security

// Keychain writes in place (NotchBuddy/Sources/App/KeychainWrite.swift): the fake Security calls play "not found", "refused" and "added" without touching the real Keychain.
// The source pins at the end read the app's files as text, so a change that brings back delete-then-add fails here.
// Run from the repository root through scripts/test-keychain-write.sh. The data is dummy bytes and the names are dummies: nothing here is a key, and nothing prints the value.

/// Records what the fake Security calls were given, in the order they were called.
final class CallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var log: [String] = []
    private var queries: [[String: Any]] = []
    private var changes: [[String: Any]] = []
    private var items: [[String: Any]] = []

    func update(_ query: [String: Any], _ attributes: [String: Any]) {
        lock.withLock {
            log.append("update")
            queries.append(query)
            changes.append(attributes)
        }
    }

    func add(_ item: [String: Any]) {
        lock.withLock {
            log.append("add")
            items.append(item)
        }
    }

    var events: [String] { lock.withLock { log } }
    var query: [String: Any]? { lock.withLock { queries.first } }
    var attributes: [String: Any]? { lock.withLock { changes.first } }
    var item: [String: Any]? { lock.withLock { items.first } }
}

@main
enum KeychainWriteTests {
    static let service = "test.service"
    static let account = "test.account"
    static let data = Data([1, 2, 3])

    static func fake(update: OSStatus, add: OSStatus) -> (KeychainWrite.Calls, CallRecorder) {
        let recorder = CallRecorder()
        let calls = KeychainWrite.Calls(
            update: { query, attributes in
                recorder.update(query as! [String: Any], attributes as! [String: Any])
                return update
            },
            add: { item in
                recorder.add(item as! [String: Any])
                return add
            })
        return (calls, recorder)
    }

    static func run(update: OSStatus, add: OSStatus) -> (saved: Bool, calls: CallRecorder) {
        let (calls, recorder) = fake(update: update, add: add)
        let saved = KeychainWrite.save(service: service, account: account, data: data, calls: calls)
        return (saved, recorder)
    }

    static func keys(_ dict: [String: Any]?) -> Set<String> { Set((dict ?? [:]).keys) }
    static func text(_ dict: [String: Any]?, _ key: CFString) -> String? { dict?[key as String] as? String }

    static func source(_ file: String) -> String {
        (try? String(contentsOfFile: "NotchBuddy/Sources/App/\(file)", encoding: .utf8)) ?? ""
    }
    static func count(_ needle: String, in text: String) -> Int { text.components(separatedBy: needle).count - 1 }
    static func at(_ needle: String, in text: String) -> String.Index? { text.range(of: needle)?.lowerBound }
    /// The text from the start marker up to the end marker (empty when either is missing).
    static func between(_ text: String, _ start: String, _ end: String) -> String {
        guard let from = text.range(of: start), let to = text.range(of: end, range: from.upperBound..<text.endIndex) else { return "" }
        return String(text[from.lowerBound..<to.lowerBound])
    }

    @MainActor static func main() {
        let genericPassword = kSecClassGenericPassword as String
        let whenUnlocked = kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String

        CT.section("update succeeds: the value is written in place and nothing is added")
        let (saved1, r1) = run(update: errSecSuccess, add: errSecSuccess)
        CT.checkTrue("save returns true", saved1)
        CT.check("the calls are update only", r1.events, ["update"])
        CT.check("the update query has exactly class, service and account", keys(r1.query), Set<String>([kSecClass as String, kSecAttrService as String, kSecAttrAccount as String]))
        CT.checkTrue("the query's class is generic password", text(r1.query, kSecClass) == genericPassword)
        CT.checkTrue("the query names the given service and account", text(r1.query, kSecAttrService) == service && text(r1.query, kSecAttrAccount) == account)
        CT.check("the update attributes are exactly the value and the access", keys(r1.attributes), Set<String>([kSecValueData as String, kSecAttrAccessible as String]))
        CT.checkTrue("the update writes the given data", (r1.attributes?[kSecValueData as String] as? Data) == data)
        CT.checkTrue("the update keeps WhenUnlockedThisDeviceOnly", text(r1.attributes, kSecAttrAccessible) == whenUnlocked)

        CT.section("update finds nothing: one add, with the strictest access and never synchronised")
        let (saved2, r2) = run(update: errSecItemNotFound, add: errSecSuccess)
        CT.checkTrue("save returns true", saved2)
        CT.check("update first, then one add", r2.events, ["update", "add"])
        CT.check("the add item has exactly its six keys", keys(r2.item), Set<String>([kSecClass as String, kSecAttrService as String, kSecAttrAccount as String, kSecValueData as String, kSecAttrAccessible as String, kSecAttrSynchronizable as String]))
        CT.checkTrue("the add item names the class, service and account", text(r2.item, kSecClass) == genericPassword && text(r2.item, kSecAttrService) == service && text(r2.item, kSecAttrAccount) == account)
        CT.checkTrue("the add item carries the data", (r2.item?[kSecValueData as String] as? Data) == data)
        CT.checkTrue("the add item keeps WhenUnlockedThisDeviceOnly", text(r2.item, kSecAttrAccessible) == whenUnlocked)
        CT.checkTrue("the add item is never synchronised to iCloud", (r2.item?[kSecAttrSynchronizable as String] as? Bool) == false)

        CT.section("update finds nothing and the add is refused: false, one add tried")
        for status in [errSecDuplicateItem, errSecInteractionNotAllowed] {
            let (saved, r) = run(update: errSecItemNotFound, add: status)
            CT.checkTrue("add refused (\(status)): save returns false", !saved)
            CT.check("add refused (\(status)): update, then one add", r.events, ["update", "add"])
        }

        CT.section("update refused: false, and no add, so the old value is never removed")
        for status in [errSecInteractionNotAllowed, errSecAuthFailed] {
            let (saved, r) = run(update: status, add: errSecSuccess)
            CT.checkTrue("update refused (\(status)): save returns false", !saved)
            CT.check("update refused (\(status)): only the update was called", r.events, ["update"])
        }

        CT.section("every combination: update first, add at most once, and an add only after 'not found'")
        var rule = true
        for update in [errSecSuccess, errSecItemNotFound, errSecInteractionNotAllowed, errSecAuthFailed, errSecParam] {
            for add in [errSecSuccess, errSecDuplicateItem, errSecInteractionNotAllowed] {
                let (_, r) = run(update: update, add: add)
                let expected = update == errSecItemNotFound ? ["update", "add"] : ["update"]
                if r.events != expected { rule = false }
            }
        }
        CT.checkTrue("the calls are exactly as the rule says in all 15 combinations", rule)

        CT.section("wiring: Keychain.save calls the in-place writer and no longer deletes or adds itself")
        let claude = source("ClaudeService.swift"), writer = source("KeychainWrite.swift")
        CT.checkTrue("both files were read", claude.contains("enum Keychain {") && writer.contains("enum KeychainWrite"))
        let save = between(claude, "static func save(key: String, value: String)", "static func load(key:")
        CT.checkTrue("Keychain.save ends by calling KeychainWrite.save with its service, account and data", save.contains("return KeychainWrite.save(service: service, account: key, data: data)"))
        CT.check("Keychain.save has no SecItemDelete", count("SecItemDelete", in: save), 0)
        CT.check("Keychain.save has no SecItemAdd", count("SecItemAdd", in: save), 0)
        CT.check("KeychainWrite.swift has no SecItemDelete", count("SecItemDelete", in: writer), 0)
        let updateAt = at("SecItemUpdate", in: writer), addAt = at("SecItemAdd", in: writer)
        CT.checkTrue("KeychainWrite.swift calls SecItemUpdate before SecItemAdd", updateAt != nil && addAt != nil && updateAt! < addAt!)
        CT.checkTrue("and adds only after errSecItemNotFound", writer.contains("guard updated == errSecItemNotFound else"))
        CT.check("ClaudeService.swift keeps exactly one SecItemDelete", count("SecItemDelete", in: claude), 1)
        CT.checkTrue("and it is still in Keychain.delete, which reports success for a deleted or an absent item", between(claude, "static func delete(key: String) -> Bool {", "// MARK: - Keychain cache").contains("SecItemDelete"))
        let deleteBody = between(claude, "static func delete(key: String) -> Bool {", "// MARK: - Keychain cache")
        CT.checkTrue("Keychain.delete is true only for errSecSuccess or errSecItemNotFound", deleteBody.contains("let status = SecItemDelete(query as CFDictionary)") && deleteBody.contains("return status == errSecSuccess || status == errSecItemNotFound"))
        let removeBody = between(claude, "func remove(_ key: String) -> Bool {", "// MARK: - Claude API")
        let askAt = at("guard Keychain.delete(key: key) else { return false }", in: removeBody), clearAt = at("lock.withLock { cache[key] = nil }", in: removeBody)
        CT.checkTrue("KeychainStore.remove always asks the Keychain (no cache check first), clears the cache only after it took the delete", askAt != nil && clearAt != nil && askAt! < clearAt! && removeBody.contains("return true") && !removeBody.contains("if had") && !removeBody.contains("let had"))
        CT.check("Keychain.delete is called from one place only: KeychainStore.remove", count("Keychain.delete(", in: claude), 1)
        CT.checkTrue("the service line is unchanged", claude.components(separatedBy: "\n").contains("    static let service = \"io.github.aikusan.notchmeow\""))
        let keychainEnum = between(claude, "enum Keychain {", "// MARK: - Claude API")
        CT.checkTrue("nothing logs a value: no print, Log, NSLog or os_log in the Keychain code", ["print(", "Log.", "NSLog", "os_log"].allSatisfy { !keychainEnum.contains($0) && !writer.contains($0) })

        CT.finish()
    }
}
