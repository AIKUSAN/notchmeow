import SwiftUI

// Settings → AI and chat → Companion (F3a, Task 9): four cards built from the kit (SettingsCard, SettingRow, SwitchRow, HelpText, WrapRow). The view takes plain values and
// closures: it reads neither the app's state nor the companion's store, and writes no key (SettingsView's closures do). "What the AI saw last" opens
// a sheet of the lines the last request sent: memory only, shown here and nowhere else. Tests: tests/CompanionWiringTests.swift (scripts/test-companion-wiring.sh).

struct CompanionTab: View {
    /// What the tab shows. `lastSent` is the full text of what the last request sent to the brain; it is kept in memory only and never leaves the sheet.
    struct Model: Equatable {
        var humor: String
        var seeSessions: Bool
        var brain: String
        var conversations: Int
        var lastSent: [String]
    }

    let model: Model
    let setHumor: (String) -> Void
    let setSeeSessions: (Bool) -> Void
    let deleteAll: () -> Void
    @State private var askingDeleteAll = false
    @State private var showingLastSent = false

    init(model: Model, setHumor: @escaping (String) -> Void, setSeeSessions: @escaping (Bool) -> Void, deleteAll: @escaping () -> Void) {
        self.model = model
        self.setHumor = setHumor
        self.setSeeSessions = setSeeSessions
        self.deleteAll = deleteAll
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard("Personality") {
                SettingRow("Humor") {
                    Picker("", selection: Binding(get: { model.humor }, set: { setHumor($0) })) {
                        Text("Off").tag("off")
                        Text("A little").tag("little")
                        Text("More").tag("more")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                HelpText("The cat's traits come from Cat → Personality. While an agent waits for you, it makes no jokes.")
            }
            SettingsCard("What the chat knows") {
                SwitchRow("See my sessions", help: CompanionChrome.sentTo(model.brain), isOn: Binding(get: { model.seeSessions }, set: { setSeeSessions($0) }))
                HelpText("Project names and what your Claude Code sessions are doing, never a path or what was written.")
            }
            SettingsCard("Conversations") {
                SettingRow("\(model.conversations) saved") {
                    Button("Delete all…") { askingDeleteAll = true }
                }
                HelpText("Kept on this Mac, 50 at most; the oldest unpinned goes first.")
            }
            SettingsCard("What the AI saw last") {
                WrapRow { Button("Show") { showingLastSent = true } }
                HelpText("Kept in memory only, gone when NotchMeow quits.")
            }
        }
        .confirmationDialog("Delete all saved conversations?", isPresented: $askingDeleteAll, titleVisibility: .visible) {
            Button("Delete all", role: .destructive) { deleteAll() }
        } message: {
            Text("Every saved conversation on this Mac is deleted. This cannot be undone.")
        }
        .sheet(isPresented: $showingLastSent) { lastSentSheet }
    }

    private var lastSentSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What the AI saw last").font(.headline)
            ScrollView {
                Text(model.lastSent.isEmpty ? "Nothing sent since NotchMeow started." : model.lastSent.joined(separator: "\n"))
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            HStack {
                Spacer()
                Button("Done") { showingLastSent = false }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(minWidth: 420, idealWidth: 440, minHeight: 300, idealHeight: 360)
        .accessibilityIdentifier(CompanionFiles.marker)
    }
}
