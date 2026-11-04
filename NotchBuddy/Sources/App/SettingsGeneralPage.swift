import SwiftUI

// Settings → General, the General tab: four cards (Sound, Island, On the island, Startup). The tab takes a model of bindings and plain values, so the render script draws it from
// samples and the app fills it from AppState (Task 10). Nothing here reads a store. The Shortcuts tab is ShortcutsSettingsView. Help texts are the ones the old tab's tooltips held.

struct GeneralSettingsModel {
    var soundEnabled: Binding<Bool>
    var soundVolume: Binding<Double>                 // 0...0.2, shown as 0–100 %
    var openOnHover: Binding<Bool>
    var focusAware: Binding<Bool>                    // Step back when I'm already in the app (focus awareness): its row sits right after Open on hover
    var hoverGlow: Binding<Bool>
    var tuckAway: Binding<IslandTuckAway.Choice>
    var closeAfter: Binding<TimeInterval>
    var mainPill: Binding<String>
    var mainChoices: [(id: String, name: String)]
    var slots: SettingsStatus.Slots
    var slotLinks: [(name: String, place: SettingsRoute.Place)]
    var launchAtStartup: Binding<Bool>
    var open: (SettingsRoute.Place) -> Void
}

struct GeneralSettingsTab: View {
    let model: GeneralSettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard("Sound") {
                SwitchRow("Enable sounds", isOn: model.soundEnabled)
                SettingRow("Volume") {
                    HStack(spacing: 8) {
                        Slider(value: model.soundVolume, in: 0...0.2)
                            .disabled(!model.soundEnabled.wrappedValue)
                            .frame(minWidth: 120, idealWidth: 180, maxWidth: SettingsLayout.fieldMax)
                        Text("\(Int(model.soundVolume.wrappedValue / 0.2 * 100)) %")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }

            SettingsCard("Island") {
                SwitchRow("Open on hover", help: "Hovering the island opens it; it folds again shortly after the pointer leaves. Click inside to keep it open.", isOn: model.openOnHover)
                SwitchRow("Step back when I'm already in the app", help: "When an agent asks for permission or a question while its app is in front, it asks there: the island stays closed and quiet, and an amber dot on its pill shows it is waiting.", isOn: model.focusAware)
                SwitchRow("Hover glow", help: "A soft rainbow glow along the island's edge while the pointer is over it.", isOn: model.hoverGlow)
                SettingRow("Tuck the island away", help: "The compact island hides by itself only when no agent is working or waiting, and this long has passed since the last hook event, alert or click on the island. Never keeps it up.") {
                    Picker("", selection: model.tuckAway) {
                        Text("Never").tag(IslandTuckAway.Choice.never)
                        Text("After 1 min").tag(IslandTuckAway.Choice.m1)
                        Text("After 5 min").tag(IslandTuckAway.Choice.m5)
                        Text("After 15 min").tag(IslandTuckAway.Choice.m15)
                        Text("After 30 min").tag(IslandTuckAway.Choice.m30)
                    }
                    .labelsHidden()
                    .frame(width: SettingsLayout.pickerWidth, alignment: .leading)
                }
                SettingRow("Close after") {
                    HStack(spacing: 8) {
                        TextField("60", value: model.closeAfter, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: SettingsLayout.numberField)
                        Text("seconds")
                    }
                }
            }

            SettingsCard("On the island") {
                SettingRow("Main pill") {
                    Picker("", selection: model.mainPill) {
                        ForEach(model.mainChoices.indices, id: \.self) { i in
                            Text(model.mainChoices[i].name).tag(model.mainChoices[i].id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: SettingsLayout.pickerWidth, alignment: .leading)
                }
                Text(model.slots.text)
                    .font(.system(size: 12))
                    .foregroundColor(model.slots.full ? .orange : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                WrapRow {
                    ForEach(model.slotLinks.indices, id: \.self) { i in
                        Button(model.slotLinks[i].name) { model.open(model.slotLinks[i].place) }
                            .buttonStyle(.link)
                    }
                }
                HelpText("Each pill's switch is on the Agents, AI and chat and Services pages.")
            }

            SettingsCard("Startup") {
                SwitchRow("Launch at Mac startup", isOn: model.launchAtStartup)
            }
        }
    }
}
