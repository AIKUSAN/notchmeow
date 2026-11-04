import Foundation

// The words and the switches the Settings pages show beside a pill, a key or a service: the four-slot cap, the chips and the dot each chip gets (one table, so every chip of the same
// word has the same dot). A missing prerequisite never disables a switch (rule 10); only the cap does. Pure Foundation; tests: tests/SettingsRulesTests.swift (scripts/test-settings-rules.sh).

enum SettingsStatus {
    struct Slots: Equatable, Sendable {
        var text: String
        var names: [String]
        var full: Bool
    }

    struct PillSwitch: Equatable, Sendable {
        var showsSwitch: Bool
        var chip: String?
        var disabled: Bool
    }

    enum Tone: Sendable { case ok, warn, neutral, error }

    static let maxSlots = 4
    static let capSentence = "4 of 4 slots used. Turn another off."

    /// The slot count, and the names of the active pills in catalog order (an id the catalog does not hold is counted but not named).
    static func slots(active: Set<String>, catalog: [(id: String, name: String)]) -> Slots {
        Slots(text: "\(active.count) of \(maxSlots) slots used",
              names: catalog.filter { active.contains($0.id) }.map(\.name),
              full: active.count >= maxSlots)
    }

    /// The main pill has no switch and says "Main". An off pill at the cap is disabled with the cap sentence; otherwise the chip is the missing prerequisite, if any, and never disables.
    static func pillSwitch(isOn: Bool, isMain: Bool, activeCount: Int, missing: String?) -> PillSwitch {
        if isMain { return PillSwitch(showsSwitch: false, chip: "Main", disabled: false) }
        if !isOn && activeCount >= maxSlots { return PillSwitch(showsSwitch: true, chip: capSentence, disabled: true) }
        return PillSwitch(showsSwitch: true, chip: missing, disabled: false)
    }

    /// "Needs update" wins; nil when the hooks' state is not known.
    static func hookChip(installed: Bool?, needsUpdate: Bool) -> String? {
        if needsUpdate { return "Needs update" }
        if let installed { return installed ? "Installed" : "Not installed" }
        return nil
    }

    static func keyChip(saved: Bool) -> String { saved ? "Ready" : "No key yet" }

    static func serviceChip(saved: Bool) -> String { saved ? "Saved" : "No key yet" }

    /// The dot a chip gets: green for the ready words, amber for what needs the user, red for "Not ready", grey for the rest.
    static func tone(_ chip: String) -> Tone {
        if ["Ready", "Installed", "Saved", "Main"].contains(chip) || chip.hasPrefix("Running") { return .ok }
        if ["Needs update", "Not saved", "Hooks not installed", "Key not configured", "Not connected", "Update needed", capSentence].contains(chip) || chip.hasPrefix("Off") { return .warn }
        if chip == "Not ready" { return .error }
        return .neutral
    }
}
