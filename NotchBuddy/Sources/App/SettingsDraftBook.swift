import Foundation

// The text a Settings field shows: what the user typed (not yet saved), or what is stored. Each card's Save writes only its own fields, and a half-typed value is never saved by a tab or
// page change (the restyle spec's rule 11): the book keeps the typed text until `markSaved` says what was really written. Pure values; the views hold one book per Settings window.
// Tests: tests/SettingsRulesTests.swift (scripts/test-settings-rules.sh).

struct SettingsDraftBook: Equatable, Sendable {
    /// Field id → the stored value ("" when none).
    private var saved: [String: String]
    /// Field id → the text the user has typed since the last save.
    private var edits: [String: String] = [:]

    init(saved: [String: String]) { self.saved = saved }

    /// The edited text, else the saved value, else "".
    func text(_ id: String) -> String { edits[id] ?? saved[id] ?? "" }

    mutating func edit(_ id: String, _ text: String) { edits[id] = text }

    /// What was really written: a trimmed key, or "" after a removal. The field then shows exactly that.
    mutating func markSaved(_ id: String, stored: String) {
        saved[id] = stored
        edits[id] = stored
    }

    /// The text differs from what is stored.
    func isDirty(_ id: String) -> Bool { text(id) != (saved[id] ?? "") }

    /// A non-empty value is stored.
    func isSaved(_ id: String) -> Bool { !(saved[id] ?? "").isEmpty }
}
