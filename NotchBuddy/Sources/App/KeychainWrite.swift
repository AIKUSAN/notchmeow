import Foundation
import Security

// How the app's Keychain wrapper (`Keychain.save` in ClaudeService.swift) writes a value: in place. It updates the item that is there and adds one only when
// none is; it never deletes first, so a failed write leaves the old value in the Keychain. The two Security calls are passed in, so
// scripts/test-keychain-write.sh can play "not found", "add refused" and "update refused" without touching the real Keychain.
enum KeychainWrite {
    struct Calls: Sendable {
        var update: @Sendable (_ query: CFDictionary, _ attributes: CFDictionary) -> OSStatus
        var add: @Sendable (_ item: CFDictionary) -> OSStatus
        static let system = Calls(update: { SecItemUpdate($0, $1) }, add: { SecItemAdd($0, nil) })
    }

    /// True only when the Keychain took the value. Strictest access, as before: only while the Mac is unlocked, never synced to iCloud, never migrated to another device.
    static func save(service: String, account: String, data: Data, calls: Calls = .system) -> Bool {
        let lookup: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let changes: [String: Any] = [
            kSecValueData as String:      data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let updated = calls.update(lookup as CFDictionary, changes as CFDictionary)
        guard updated == errSecItemNotFound else { return updated == errSecSuccess }
        var item = lookup
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        item[kSecAttrSynchronizable as String] = kCFBooleanFalse!
        return calls.add(item as CFDictionary) == errSecSuccess
    }
}
