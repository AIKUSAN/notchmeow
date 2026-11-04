import SwiftUI

// Settings → AI and chat, its three tabs (the restyle spec's Your AI, Keys and Local models). Your AI: which model answers each feature, and the rows that make one the main choice,
// with the Claude plan's Details. Keys: one card per provider, each key once. Local models: the servers on this Mac or on the network, Apple on-device, Rescan and Add server…
// The tabs take a model of plain values and closures, so the render script draws them from samples and the app fills them (Task 11). Nothing here reads a store, the Keychain or a
// live status. The Claude state is SettingsAI.ClaudeState, which the App Store build compiles too.

/// One group of a feature's pop-up: a titled section (Cloud, Local…) or, with no title, plain items.
struct AIChoiceSection: Identifiable {
    let id: String
    var title: String?
    var items: [(label: String, value: FeatureSetting)]
}

/// One feature's row: Chat or File questions, its pop-up of choices, and what Auto resolves to.
struct AIFeatureRow: Identifiable {
    let id: AIFeature
    var label: String
    var selection: Binding<FeatureSetting>
    var sections: [AIChoiceSection]
    var resolution: String?
}

/// "When Auto picks a cloud model, prefer": shown only when two or more cloud providers are ready.
struct AIPreferModel {
    var selection: Binding<AIProviderID>
    var choices: [(id: AIProviderID, label: String)]
}

/// One row of Choose your AI: its title, one-liner, chip, what Make main does, and whether it offers an Add a key button.
struct AIRowModel: Identifiable {
    let id: SettingsAI.Row
    var title: String
    var line: String?             // nil when the chip or the button already says it (SettingsAI.helpLine)
    var chip: String
    var isMain: Bool
    var makeMain: SettingsAI.MakeMain
    var addKey: Bool
    var reason: String?           // why it cannot be made main, when the chip and the button do not already say it (SettingsAI.reasonLine)
}

/// The Claude plan's Details: today's Connect Claude controls, with plain values and closures.
struct ClaudePlanDetails {
    var state: SettingsAI.ClaudeState
    var note: String              // the plain-text note of the plan's engine, set by the builder
    var line: String
    var inUse: Bool
    var checking: Bool
    var model: Binding<ClaudeCodeModel>
    var connect: () -> Void
    var stop: () -> Void
    var checkAgain: () -> Void
    var signIn: () -> Void
    var guide: URL?
}

struct YourAIModel {
    var features: [AIFeatureRow]
    var prefer: AIPreferModel?
    var rows: [AIRowModel]
    var claude: ClaudePlanDetails?
}

/// Settings → AI and chat → Your AI: two cards. Which one answers, then Choose your AI.
struct YourAITab: View {
    let model: YourAIModel
    let setChat: (FeatureSetting) -> Void
    let openKeys: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard("Which one answers") {
                ForEach(model.features) { feature in featureRow(feature) }
                if let prefer = model.prefer { preferRow(prefer) }
            }
            SettingsCard("Choose your AI") {
                ForEach(model.rows) { row in chooserRow(row) }
            }
        }
    }

    private func featureRow(_ row: AIFeatureRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            PickerRow(row.label) {
                Picker("", selection: row.selection) {
                    Text("Auto").tag(FeatureSetting.auto)
                    ForEach(row.sections) { section in
                        if let title = section.title {
                            Section(title) { choices(section) }
                        } else {
                            choices(section)
                        }
                    }
                }
                .labelsHidden()
            }
            if row.selection.wrappedValue == .auto, let resolution = row.resolution { HelpText(resolution) }
        }
    }

    @ViewBuilder private func choices(_ section: AIChoiceSection) -> some View {
        ForEach(section.items.indices, id: \.self) { i in
            Text(section.items[i].label).tag(section.items[i].value)
        }
    }

    private func preferRow(_ prefer: AIPreferModel) -> some View {
        PickerRow("When Auto picks a cloud model, prefer") {
            Picker("", selection: prefer.selection) {
                ForEach(prefer.choices.indices, id: \.self) { i in
                    Text(prefer.choices[i].label).tag(prefer.choices[i].id)
                }
            }
            .labelsHidden()
        }
    }

    /// The title is semibold 12 pt, its chip and buttons sit in the control (13 pt, so they keep their own size).
    private func chooserRow(_ row: AIRowModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingRow(row.title, help: row.line) {
                HStack(spacing: 8) {
                    StatusChip(row.chip)
                    makeMainControl(row)
                    if row.addKey { Button("Add a key") { openKeys() }.buttonStyle(.bordered) }
                }
                .font(.system(size: 13))
            }
            .font(.system(size: 12, weight: .semibold))
            if let reason = row.reason { HelpText(reason) }
            if row.id == .claudePlan, let claude = model.claude { ClaudeDetails(claude: claude) }
        }
    }

    @ViewBuilder private func makeMainControl(_ row: AIRowModel) -> some View {
        if row.isMain {
            StatusChip("Main")
        } else {
            switch row.makeMain {
            case .set(let setting):
                Button("Make main") { setChat(setting) }.buttonStyle(.bordered)
            case .menu(let refs):
                // One item per model of the server, the model used last first; the model id is a pop-up item, never wrapped text.
                Menu("Make main") {
                    ForEach(refs.indices, id: \.self) { i in
                        Button(refs[i].model) { setChat(.explicit(refs[i])) }
                    }
                }
                .fixedSize()
            case .unavailable:
                Button("Make main") {}.buttonStyle(.bordered).disabled(true)
            }
        }
    }
}

/// The Claude plan's Details, closed until opened: its line, the one button its state gives, Check again, the model, and what NotchMeow does not do.
private struct ClaudeDetails: View {
    let claude: ClaudePlanDetails

    var body: some View {
        DisclosureGroup("Details") {
            VStack(alignment: .leading, spacing: 10) {
                HelpText(claude.note)
                HelpText(claude.line)
                WrapRow { stateButtons }
                PickerRow("Model") {
                    Picker("", selection: claude.model) {
                        ForEach(ClaudeCodeModel.allCases, id: \.self) { model in Text(model.label).tag(model) }
                    }
                    .labelsHidden()
                }
                HelpText("NotchMeow never signs in to Claude and never reads Claude Code's credentials.")
            }
            .padding(.top, 6)
        }
    }

    @ViewBuilder private var stateButtons: some View {
        switch claude.state {
        case .signedIn:
            if claude.inUse {
                Text("Claude is now your main AI.").font(.system(size: 11)).foregroundColor(Color(hex: "#22C55E"))
                Button("Stop using it", action: claude.stop).buttonStyle(.bordered)
            } else {
                Button("Use my Claude plan", action: claude.connect).buttonStyle(.borderedProminent)
            }
        case .signedOut:
            Button("Sign in", action: claude.signIn).buttonStyle(.borderedProminent)
        case .notInstalled, .tooOld:
            if let guide = claude.guide {
                Link(claude.state == .tooOld ? "How to update" : "How to install", destination: guide).font(.system(size: 11))
            }
        case .unknown:
            EmptyView()
        }
        Button(claude.checking ? "Checking…" : "Check again", action: claude.checkAgain)
            .buttonStyle(.bordered)
            .disabled(claude.checking)
    }
}

/// A label and a pop-up, laid out as SettingRow lays out a row, with the pop-up's width set here: pickerWidth beside the label, and the whole row when the
/// label stacks above it (a pop-up of pickerWidth in a full-width row left a gap, and a long choice cannot wrap in it).
private struct PickerRow<Control: View>: View {
    let label: String
    let picker: Control

    init(_ label: String, @ViewBuilder picker: () -> Control) {
        self.label = label; self.picker = picker()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                Text(label).fixedSize()
                Spacer(minLength: 12)
                picker.frame(width: SettingsLayout.pickerWidth, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(label).fixedSize(horizontal: false, vertical: true)
                picker.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Keys

/// One provider's key card: its colour, the key field and its buttons, the island switch when it has a pill, its help, and for Anthropic the model.
struct KeyCardModel: Identifiable {
    var id: AIProviderID { provider }
    var provider: AIProviderID
    var name: String
    var color: String
    var help: String
    var fieldId: String           // the Keychain item
    var placeholder: String
    var works: Bool?
    var pill: PillSwitchModel?
    var anthropicModel: AnthropicModelPicker?
}

/// The Anthropic model pop-up (its presets, then Custom…) and the field a custom model id is typed in.
struct AnthropicModelPicker {
    var choice: Binding<String>
    var options: [(id: String, label: String)]
    var customTag: String
    var custom: Binding<String>
}

struct KeysTab: View {
    let cards: [KeyCardModel]
    let text: (String) -> Binding<String>
    let dirty: (String) -> Bool
    let saved: (String) -> Bool
    let save: (AIProviderID) -> Void
    let remove: (AIProviderID) -> Void
    let toggle: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(cards) { card in keyCard(card) }
        }
    }

    private func keyCard(_ card: KeyCardModel) -> some View {
        SettingsCard(card.name, dot: Color(hex: card.color)) {
            KeyRow(card.placeholder, text: text(card.fieldId), saved: saved(card.fieldId), dirty: dirty(card.fieldId), works: card.works,
                   save: { save(card.provider) }, remove: { remove(card.provider) })
            if let pill = card.pill { PillSwitchRow(pill: pill, label: "Show on the island", toggle: toggle) }
            HelpText(card.help)
            if let picker = card.anthropicModel { anthropicModelRows(picker) }
        }
    }

    @ViewBuilder private func anthropicModelRows(_ m: AnthropicModelPicker) -> some View {
        PickerRow("Model") {
            Picker("", selection: m.choice) {
                ForEach(m.options.indices, id: \.self) { i in Text(m.options[i].label).tag(m.options[i].id) }
                Text("Custom…").tag(m.customTag)
            }
            .labelsHidden()
        }
        if m.choice.wrappedValue == m.customTag {
            TextField("Model ID (e.g. claude-sonnet-5-5)", text: m.custom)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: SettingsLayout.fieldMax)
        }
        HelpText("Used by the chat. The list comes from your Anthropic account.")
    }
}

// MARK: - Local models

/// One server: its name, its chip, the get or update link and Remove (when the user added it), its network note, and its island switch.
struct ServerRowModel: Identifiable {
    let id: String
    var name: String
    var chip: String
    var ready: Bool
    var network: String?
    var getLink: (label: String, url: URL)?
    var removable: Bool
    var pill: PillSwitchModel?
    var note: String?             // help text under the row, e.g. a server with no model yet (SettingsAI.makeMain's words)
}

struct LocalModelsModel {
    var servers: [ServerRowModel]
    var apple: String?
    var rescanning: Bool
}

struct LocalModelsTab: View {
    let model: LocalModelsModel
    @Binding var showAddServer: Bool
    let rescan: () -> Void
    let remove: (String) -> Void
    let toggle: (String) -> Void
    let addServer: (_ name: String, _ baseURL: String, _ key: String?) -> Void

    var body: some View {
        SettingsCard("Local models") {
            HelpText("Models running on this Mac, or on a server you add. Found automatically on this Mac only.")
            ForEach(model.servers) { server in serverRow(server) }
            if let apple = model.apple {
                SettingRow("Apple on-device") { StatusChip(apple) }
            }
            WrapRow {
                Button(model.rescanning ? "Scanning…" : "Rescan", action: rescan)
                    .buttonStyle(.bordered)
                    .disabled(model.rescanning)
                Button("Add server…") { showAddServer = true }.buttonStyle(.bordered)
            }
        }
        .sheet(isPresented: $showAddServer) {
            AddServerSheet(isPresented: $showAddServer, onAdd: addServer)
        }
    }

    private func serverRow(_ server: ServerRowModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                dot(server.ready).padding(.top, 5)
                VStack(alignment: .leading, spacing: 4) {
                    Text(server.name).font(.system(size: 12, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    StatusChip(server.chip)
                }
            }
            if server.getLink != nil || server.removable {
                WrapRow {
                    if let link = server.getLink { Link(link.label, destination: link.url).font(.system(size: 11)) }
                    if server.removable { Button("Remove") { remove(server.id) }.buttonStyle(.bordered) }
                }
            }
            if let network = server.network { HelpText(network) }
            if let note = server.note { HelpText(note) }
            if let pill = server.pill { PillSwitchRow(pill: pill, label: "Show on the island", toggle: toggle) }
        }
    }

    /// A filled green dot when the server has models, a ring otherwise.
    @ViewBuilder private func dot(_ ready: Bool) -> some View {
        if ready {
            Circle().fill(Color(hex: "#22C55E")).frame(width: 8, height: 8)
        } else {
            Circle().stroke(Color.secondary, lineWidth: 1).frame(width: 8, height: 8)
        }
    }
}
