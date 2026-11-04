import SwiftUI

// The text of the Settings fields kept in the Keychain (the three AI keys and every service's fields), one holder for the Settings window's life. It keeps what the user has typed
// until a Save writes it (the restyle spec's rule 11: a tab or page change never saves a half-typed key). The rules are SettingsDraftBook's; this class only publishes them.
// Seeded once, in `init`, from the Keychain: create it outside any view body, never during an update.

@MainActor
final class SettingsDrafts: ObservableObject {
    /// Every Keychain field the Settings pages edit: the three AI keys (AICatalog's Keychain names), then the service fields, grouped by
    /// pill id in sorted order (SettingsMap.serviceFields keys, sorted; each group keeps its own field order).
    static let fieldIds: [String] = [AIProviderID.anthropic, .google, .openai].map { AICatalog.info($0).keychainKey! }
        + SettingsMap.serviceFields.keys.sorted().flatMap { SettingsMap.serviceFields[$0] ?? [] }

    @Published private(set) var book: SettingsDraftBook

    init(read: (String) -> String) {
        var saved: [String: String] = [:]
        for id in Self.fieldIds { saved[id] = read(id) }
        book = SettingsDraftBook(saved: saved)
    }

    func text(_ id: String) -> Binding<String> {
        Binding(get: { self.book.text(id) }, set: { self.book.edit(id, $0) })
    }

    func isDirty(_ id: String) -> Bool { book.isDirty(id) }

    func isSaved(_ id: String) -> Bool { book.isSaved(id) }

    /// What was really written to the Keychain: the value saved, or "" after a removal.
    func markSaved(_ id: String, stored: String) { book.markSaved(id, stored: stored) }
}
