import SwiftUI
import AppKit

/// Settings → General → Shortcuts: the global shortcuts (a switch and a key each) and a read-only list of the island's own.
struct ShortcutsSettingsView: View {
    @Environment(\.settingsMode) private var settingsMode
    @State private var enabled: [ShortcutAction: Bool] = [:]
    @State private var specs: [ShortcutAction: ShortcutSpec] = [:]
    /// Shortcuts macOS refused to register: another app already has that combination.
    @State private var takenElsewhere: Set<ShortcutAction> = []
    /// Two of NotchMeow's own shortcuts on one combination.
    @State private var duplicates: Set<ShortcutAction> = []
    /// What "Turn all on" left off, and why.
    @State private var leftOff: [ShortcutLogic.TurnOnResult] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            globalGroup
            islandGroup
        }
        .onAppear { reload() }
    }

    // MARK: Global shortcuts

    private var globalGroup: some View {
        SettingsCard("Global shortcuts") {
            HelpText("Work from any app. Use ⌘ or ⌃ with another modifier.")
            ForEach(ShortcutLogic.available(), id: \.self) { action in
                row(action)
            }
            WrapRow {
                Button("Turn all on") { turnAllOn() }
                    .controlSize(.small)
                Button("Reset to defaults") { resetAll() }
                    .controlSize(.small)
            }
            if let summary = ShortcutLogic.turnOnSummary(leftOff) {
                Text(summary)
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// One shortcut: its name, and its switch, key recorder and conflict tags in one line (on as many lines as the column needs). Why it starts off is the row's help line, while it is off.
    private func row(_ action: ShortcutAction) -> some View {
        let isOn = enabled[action] ?? action.enabledByDefault
        let fallback = ShortcutLogic.defaults[action]!
        return SettingRow(action.displayName, help: isOn ? nil : action.offAtFirstNote) {
            WrapRow {
                Toggle(action.displayName, isOn: Binding(
                    get: { isOn },
                    set: { setEnabled($0, for: action) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                ShortcutRecorderButton(
                    flags: Binding(
                        get: { (specs[action] ?? fallback).nsFlags },
                        set: { specs[action, default: fallback].nsFlags = $0 }
                    ),
                    code: Binding(
                        get: { (specs[action] ?? fallback).keyCode },
                        set: { specs[action, default: fallback].keyCode = $0 }
                    ),
                    onRecorded: { commit(action) }
                )
                .disabled(!isOn)
                .opacity(isOn ? 1 : 0.5)
                conflictTag(for: action)
            }
        }
    }

    /// "Duplicate" wins over "In use elsewhere" on a row that has both. A shortcut that "Turn all on" left off keeps
    /// its tag until it is changed.
    @ViewBuilder
    private func conflictTag(for action: ShortcutAction) -> some View {
        let refusal = leftOff.first { $0.action == action }?.reason
        if duplicates.contains(action) {
            tag("Duplicate", color: .red)
        } else if case .duplicate = refusal {
            tag("Duplicate", color: .red)
        } else if takenElsewhere.contains(action) {
            tag("In use elsewhere", color: .orange)
        } else if case .taken = refusal {
            tag("In use elsewhere", color: .orange)
        }
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    // MARK: The island's own shortcuts

    /// The keys in a 90 pt column beside the action when the window is expanded; the keys above the action in the collapsed (icons) sidebar's narrower column.
    private var islandGroup: some View {
        SettingsCard("In the island") {
            HelpText("Work while the island has the keyboard. Opening it with a shortcut gives it the keyboard until you close it. In the chat, ⌘ with an arrow key still moves the cursor.")
            ForEach(Array(ShortcutLogic.islandShortcuts.enumerated()), id: \.offset) { _, shortcut in
                let key = Text(shortcut.key)
                    .font(.system(size: 11, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
                if settingsMode == .expanded {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        key.frame(width: 90, alignment: .leading)
                        HelpText(shortcut.description)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        key
                        HelpText(shortcut.description)
                    }
                }
            }
        }
    }

    // MARK: Changes

    private func reload() {
        for action in ShortcutLogic.available() {
            enabled[action] = ShortcutLogic.isEnabled(action)
            specs[action] = ShortcutLogic.hotKey(for: action)
        }
        leftOff = []
        refreshConflicts()
    }

    private func setEnabled(_ on: Bool, for action: ShortcutAction) {
        enabled[action] = on
        leftOff.removeAll { $0.action == action }
        ShortcutLogic.setEnabled(on, for: action)
        HotKeyCenter.shared.reregister(action)
        refreshConflicts()
    }

    /// A combination was recorded for `action`: keep it and register it.
    private func commit(_ action: ShortcutAction) {
        guard let spec = specs[action] else { return }
        leftOff.removeAll { $0.action == action }
        ShortcutLogic.save(spec, for: action)
        HotKeyCenter.shared.reregister(action)
        refreshConflicts()
    }

    private func resetAll() {
        for action in ShortcutLogic.available() { ShortcutLogic.resetToDefault(action) }
        HotKeyCenter.shared.registerAll()
        reload()
    }

    /// Turns on every shortcut whose combination is free. One that macOS refuses (another app has it) or that
    /// another NotchMeow shortcut already has stays off, and is reported, with a beep like a refused recording.
    private func turnAllOn() {
        let refused = ShortcutLogic.turnAllOn { action in
            HotKeyCenter.shared.reregister(action)
            return !HotKeyCenter.shared.conflicts.contains(action)
        }
        for result in refused { HotKeyCenter.shared.reregister(result.action) }   // off again: let go of it
        reload()
        leftOff = refused
        if !refused.isEmpty { NSSound.beep() }
    }

    private func refreshConflicts() {
        takenElsewhere = HotKeyCenter.shared.conflicts
        duplicates = ShortcutLogic.duplicates(in: ShortcutLogic.activeSpecs())
    }
}
