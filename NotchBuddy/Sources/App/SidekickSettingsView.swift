import SwiftUI

// Settings → AI and chat → Sidekick, the restyle spec's Sidekick tab: five cards built from the kit (SettingsCard, SwitchRow, SettingRow, StatusChip, HelpText). Notes holds the switches and an example of
// each kind; Quiet times, Jokes and moods, "My main AI" and "Today so far" come with F3a, so they are shown disabled. The permission line is always on: a locked switch with the line that says
// why. Everything it shows is `SidekickStore.settings`, and every change goes through the store, which cleans it and saves it. The view takes plain values so the render script can draw it
// without the app (`SidekickSettingsSection` below reads the one thing only the app knows: which local model was found).

struct SidekickSettingsView: View {
    @ObservedObject var store: SidekickStore
    /// The local model the voice would use ("Local · qwen3.5:2b"), or nil when none was found.
    let found: String?
    /// The kind whose example is drawn under its row (nil: none). Show me an example turns it on and off.
    @State private var shownExample: String?

    /// `example` opens one example at first: the app opens none; the render script opens one so the picture shows it.
    init(store: SidekickStore, found: String?, example: String? = nil) {
        _store = ObservedObject(wrappedValue: store)
        self.found = found
        _shownExample = State(initialValue: example)
    }

    /// The five kinds of note, as the user knows them.
    static let kindNames: [(kind: String, label: String)] = [
        ("recap", "Away recaps"), ("stuck.loop", "Repeated steps"), ("stuck.errors", "Repeated errors"), ("stuck.waiting", "Waiting for your OK"), ("stuck.silent", "Gone quiet"),
    ]

    /// A kind's switch: on while the kind is not muted. Turning it on unmutes it, turning it off mutes it, through the store.
    private func kindSwitch(_ kind: String) -> Binding<Bool> {
        Binding(get: { !store.settings.isMuted(kind) }, set: { on in on ? store.unmute(kind) : store.mute(kind) })
    }

    /// The stuck switch: on while at least one of the four is unmuted, with "N of 4" when some are muted. Turning it off mutes all four; on unmutes all four.
    private var stuckSwitch: Binding<Bool> {
        Binding(get: { SettingsSidekick.stuckSwitch(isMuted: store.settings.isMuted).on },
                set: { on in SettingsSidekick.stuckKinds.forEach { on ? store.unmute($0) : store.mute($0) } })
    }

    var body: some View {
        let stuck = SettingsSidekick.stuckSwitch(isMuted: store.settings.isMuted)
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard("Notes") {
                SwitchRow("Show notes from the sidekick", isOn: Binding(get: { store.settings.on }, set: { store.setOn($0) }))
                VStack(alignment: .leading, spacing: 12) {
                    SwitchRow("Away recaps", help: "A short recap when you come back and an agent did something.", isOn: kindSwitch("recap"))
                    example("recap")
                    SwitchRow("Stuck nudges", help: "A nudge when an agent looks stuck.", isOn: stuckSwitch, chip: stuck.detail)
                    example("stuck.loop")
                    DisclosureGroup("Choose which") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(SettingsSidekick.stuckNames, id: \.kind) { row in
                                SwitchRow(row.label, isOn: kindSwitch(row.kind))
                            }
                        }
                        .padding(.top, 6)
                    }
                }
                .padding(.leading, 18)
                .disabled(!store.settings.on)
                SwitchRow("Permission line", help: SettingsSidekick.permissionLine, isOn: .constant(true), disabled: true)
                SwitchRow("Jokes and moods", isOn: .constant(false), chip: SettingsSidekick.comesWithF3a, disabled: true)
            }
            SettingsCard("Quiet times", summary: SettingsSidekick.comesWithF3a) {
                HelpText("Coming soon: hold notes while an app is full screen, during calls and screen sharing, and at hours you choose. Until then notes never show over your work or while you type.")
                SwitchRow("Full-screen apps", isOn: .constant(false), chip: SettingsSidekick.comesWithF3a, disabled: true)
                SwitchRow("Calls and screen sharing", isOn: .constant(false), chip: SettingsSidekick.comesWithF3a, disabled: true)
                SwitchRow("Chosen hours", isOn: .constant(false), chip: SettingsSidekick.comesWithF3a, disabled: true)
            }
            SettingsCard("Where its words come from") {
                Picker("", selection: Binding(get: { store.settings.local }, set: { store.setLocal($0) })) {
                    Text("Plain rules").tag(false)
                    Text("A model on this Mac").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)
                SettingRow("My main AI") { StatusChip(SettingsSidekick.comesWithF3a) }.disabled(true)
                if store.settings.local { HelpText(found.map { "Found: \($0)" } ?? "No local model found") }
                HelpText(SettingsSidekick.nothingLeaves)
                HelpText("Only a model on this computer is ever asked, and only with the words of the note.")
            }
            SettingsCard("Today so far", summary: SettingsSidekick.comesWithF3a) {
                HStack(spacing: 10) {
                    Button("Today so far") {}.disabled(true)
                    StatusChip(SettingsSidekick.comesWithF3a)
                }
            }
            SettingsCard("Muted notes") {
                let muted = Self.kindNames.filter { store.settings.isMuted($0.kind) }
                if muted.isEmpty {
                    HelpText("Nothing is muted")
                } else {
                    ForEach(muted, id: \.kind) { row in
                        SettingRow(row.label) { Button("Unmute") { store.unmute(row.kind) } }
                    }
                }
                HelpText("A note you dismiss twice is muted until you unmute it here.")
            }
        }
    }

    /// "Show me an example" and, when it is on, the made-up note of that kind in the island note's look (no buttons: it is a picture, not a note).
    @ViewBuilder private func example(_ kind: String) -> some View {
        Button("Show me an example") { shownExample = shownExample == kind ? nil : kind }
        if shownExample == kind, let line = SettingsSidekick.example(kind) {
            VStack(alignment: .leading, spacing: 4) {
                Text(SidekickView.title(kind))
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8"))
                Text(line)
                    .font(.system(size: 12)).foregroundColor(Color(hex: "#C8CDD4"))
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
            .background(CardBackground(wash: nil))
        }
    }
}

/// Settings → AI and chat → Sidekick in the app: the view with the model the voice would use, read again whenever the servers on this computer change.
struct SidekickSettingsSection: View {
    @ObservedObject private var store = SidekickStore.shared
    @ObservedObject private var app = AppState.shared

    var body: some View {
        SidekickSettingsView(store: store, found: SidekickVoiceApp.foundLabel())
    }
}
