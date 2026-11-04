import SwiftUI

// Settings → Agents: the switches of the agent pills on the island, one card per hook install (Claude Code, Gemini CLI, Antigravity, Codex) and the Plan usage card. The page takes
// a model of plain values and closures, so the render script draws it from samples and the app fills it (Task 10). Nothing here reads a store or a file. Every install keeps its
// preview, "Confirm & write", backup and notes; only where they sit changes.

/// One pill's row: its colour, its name, its switch (or "Main"), and the chip its state gives it.
struct PillSwitchModel: Identifiable {
    let id: String
    var name: String
    var color: String
    var isOn: Bool
    var state: SettingsStatus.PillSwitch
}

enum HookKind: String, CaseIterable { case claude, gemini, antigravity, codex }

struct HookCardModel: Identifiable {
    var id: HookKind { kind }
    var kind: HookKind
    var title: String
    var chip: String?
    var next: String?
    var path: String
    var revealable: Bool
    var note: HookNote?
    var pendingJSON: String?
    var needsUpdate: Bool
    /// Whether the hooks are installed; nil when the state is not known (the App Store build's Claude Code card). Install hooks is prominent unless this is true and no update waits.
    var installed: Bool? = nil
}

struct PlanUsageModel {
    var showInNotch: Bool
    var relayInstalled: Bool
    var note: HookNote?
    var heard: String?
    var pendingJSON: String?
}

struct AgentsSettingsModel {
    var pills: [PillSwitchModel]
    var hooks: [HookCardModel]
    var plan: PlanUsageModel?
    /// The home folder, for display only: a pending preview shows it as ~ (the file written keeps the real path).
    var home: String
}

struct AgentsSettingsActions {
    var toggle: (String) -> Void
    var install: (HookKind) -> Void
    var uninstall: (HookKind) -> Void
    var confirm: (HookKind) -> Void
    var cancel: (HookKind) -> Void
    var setShowPlan: (Bool) -> Void
    var installRelay: () -> Void
    var uninstallRelay: () -> Void
    var confirmRelay: () -> Void
    var cancelRelay: () -> Void
    var copy: (String) -> Void
    var reveal: (HookKind) -> Void
}

struct AgentsSettingsPage: View {
    let model: AgentsSettingsModel
    let actions: AgentsSettingsActions

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard("Where you code") {
                ForEach(model.pills) { pill in
                    PillSwitchRow(pill: pill, toggle: actions.toggle)
                }
            }
            ForEach(model.hooks) { card in hookCard(card, home: model.home) }
            if let plan = model.plan { planCard(plan, home: model.home) }
        }
    }

    private func hookCard(_ card: HookCardModel, home: String) -> some View {
        SettingsCard(card.title, summary: card.chip) {
            if let next = card.next { HelpText(next) }
            WrapRow {
                installButton(card, prominent: card.pendingJSON == nil)
                Button("Uninstall") { actions.uninstall(card.kind) }.buttonStyle(.bordered)
            }
            if let note = card.note { HookNoteLine(note: note) }
            if let json = card.pendingJSON {
                PendingPreview(json: SettingsLayout.displayText(json, home: home), height: 140)
                WrapRow {
                    Button("Confirm & write") { actions.confirm(card.kind) }.buttonStyle(.borderedProminent)
                    Button("Cancel") { actions.cancel(card.kind) }.buttonStyle(.bordered)
                }
            }
            PathDisclosure(path: card.path, copy: actions.copy, reveal: card.revealable ? { actions.reveal(card.kind) } : nil)
        }
    }

    /// The install or update button: prominent only when no preview is waiting for Confirm & write (then Confirm is the one prominent button), and only while the hooks
    /// are missing or outdated. An installed card's button is plain: it still reinstalls when pressed.
    @ViewBuilder private func installButton(_ card: HookCardModel, prominent: Bool) -> some View {
        let title = card.needsUpdate ? "Update hooks" : "Install hooks"
        if prominent && (card.needsUpdate || card.installed != true) {
            Button(title) { actions.install(card.kind) }.buttonStyle(.borderedProminent)
        } else {
            Button(title) { actions.install(card.kind) }.buttonStyle(.bordered)
        }
    }

    private func planCard(_ model: PlanUsageModel, home: String) -> some View {
        SettingsCard("Plan usage", summary: SettingsStatus.hookChip(installed: model.relayInstalled, needsUpdate: false)) {
            HelpText("Shows your Claude plan usage (5-hour and weekly limits) in the notch header. Pro and Max plans only.")
            DisclosureGroup("More") {
                HelpText("NotchMeow adds a status line relay to ~/.claude/settings.json. If you already have a status line, it keeps working as before.")
            }
            SwitchRow("Show in the notch", isOn: Binding(get: { model.showInNotch }, set: { actions.setShowPlan($0) }))
            WrapRow {
                if model.relayInstalled {
                    Button("Uninstall relay") { actions.uninstallRelay() }.buttonStyle(.bordered)
                } else if model.pendingJSON == nil {
                    Button("Install relay") { actions.installRelay() }.buttonStyle(.borderedProminent)
                } else {
                    Button("Install relay") { actions.installRelay() }.buttonStyle(.bordered)
                }
            }
            if let note = model.note { HookNoteLine(note: note) }
            if let heard = model.heard { HookNoteLine(note: HookNote(ok: true, text: heard)) }
            if let json = model.pendingJSON {
                PendingPreview(json: SettingsLayout.displayText(json, home: home), height: 100)
                WrapRow {
                    Button("Confirm & write") { actions.confirmRelay() }.buttonStyle(.borderedProminent)
                    Button("Cancel") { actions.cancelRelay() }.buttonStyle(.bordered)
                }
            }
            PathDisclosure(path: "~/.claude/settings.json", copy: actions.copy)
        }
    }
}

/// A pill's row: the colour dot, the name (or `label`), and the switch with the chip the state gives it; "Main" in place of the switch on the main pill. The switch is a SwitchRow,
/// so it stacks like every other row. Shared with Task 7's Keys and Local models, and Services, which label the switch "Show on the island".
struct PillSwitchRow: View {
    let pill: PillSwitchModel
    let label: String
    let dot: Bool
    let toggle: (String) -> Void

    /// `dot: false` where the card's header already carries the colour (Services).
    init(pill: PillSwitchModel, label: String? = nil, dot: Bool = true, toggle: @escaping (String) -> Void) {
        self.pill = pill; self.label = label ?? pill.name; self.dot = dot; self.toggle = toggle
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if dot { Circle().fill(Color(hex: pill.color)).frame(width: 10, height: 10).padding(.top, 5) }
            if pill.state.showsSwitch {
                SwitchRow(label, isOn: Binding(get: { pill.isOn }, set: { _ in toggle(pill.id) }), chip: pill.state.chip, disabled: pill.state.disabled)
            } else {
                HStack(spacing: 12) {
                    Text(label).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                    StatusChip("Main")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The new text an install would write: open by default, 10 pt monospaced in a scrolling box of `height`, selectable (as the install flows showed it).
struct PendingPreview: View {
    let json: String
    let height: CGFloat
    @State private var open = true

    var body: some View {
        DisclosureGroup("Preview", isExpanded: $open) {
            ScrollView {
                Text(json)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            }
            .frame(height: height)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}
