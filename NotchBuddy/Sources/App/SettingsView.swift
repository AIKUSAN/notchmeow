import SwiftUI
import AppKit

// The Settings window (the restyle plan's Task 12, the swap). SettingsShell draws the sidebar and the page's frame (SettingsPage); each page's cards come from SettingsSections.
// The stored section (`settingsSection`) and each page's tab (`settingsTab.<page>`) are read through SettingsRoute, so a tag from an earlier build lands on its page and never
// leaves a blank detail. The helpers below the view (the sidebar row, the filter row, the shortcut recorder) are the ones the old window already had.

struct SettingsView: View {
    @ObservedObject private var state = AppState.shared
    @StateObject private var controller = SettingsController()
    @StateObject private var drafts = SettingsDrafts(read: { KeychainStore.shared.get($0) ?? "" })
    @ObservedObject private var companionStore = CompanionStore.shared
    @AppStorage(SettingsRoute.sectionKey) private var storedSection = "general"
    @State private var tab: SettingsRoute.Tab?

    private var page: SettingsRoute.Page { SettingsRoute.migrate(storedSection: storedSection).page }

    private var pageBinding: Binding<SettingsRoute.Page> {
        Binding(get: { page }, set: { storedSection = $0.rawValue })
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    var body: some View {
        SettingsShell(version: appVersion, icon: NSApplication.shared.applicationIconImage, page: pageBinding) { shown in
            SettingsPage(page: shown, tab: $tab, banner: controller.banner, dismissBanner: { controller.banner = "" }) {
                content(shown, shownTab(shown))
            }
        }
        .onAppear {
            settle()
            #if !APPSTORE
            state.refreshPlanRelayState()
            #endif
            arrive()
        }
        .onChange(of: storedSection) { _, _ in settle() }
        .onChange(of: page) { _, now in
            loadTab(for: now)
            controller.banner = ""
            arrive()
        }
        .onChange(of: tab) { _, now in
            if let now { UserDefaults.standard.set(now.rawValue, forKey: SettingsRoute.tabKey(page)) }
            controller.banner = ""
        }
    }

    // MARK: - Pages and tabs

    /// Brings the stored section to its page. An old tag, or a `<page>/<tab>`, is written back as the page, and its tab is kept for that page; then the page's tab is loaded.
    private func settle() {
        select(SettingsRoute.migrate(storedSection: storedSection))
    }

    private func loadTab(for p: SettingsRoute.Page) {
        tab = SettingsRoute.tab(for: p, stored: UserDefaults.standard.string(forKey: SettingsRoute.tabKey(p)))
    }

    /// A link to a place (General's slot links, the AI empty state's buttons): its tab is kept for its page, then the page is shown.
    private func select(_ place: SettingsRoute.Place) {
        if let t = place.tab { UserDefaults.standard.set(t.rawValue, forKey: SettingsRoute.tabKey(place.page)) }
        if storedSection != place.page.rawValue { storedSection = place.page.rawValue }
        loadTab(for: place.page)
    }

    /// The tab a page shows: the current one when the page has it, else its first. A tab of another page never leaves a blank detail.
    private func shownTab(_ p: SettingsRoute.Page) -> SettingsRoute.Tab? {
        let tabs = SettingsRoute.tabs(p)
        guard let tab, tabs.contains(tab) else { return tabs.first }
        return tab
    }

    /// What a page does each time it is shown (on appearing and on each change of page, never on a timer): the AI page looks for local servers and asks Claude Code how it is.
    private func arrive() {
        guard page == .chat else { return }
        controller.fetchModelsIfNeeded()
        Task { await AIService.shared.discover() }
        #if !APPSTORE
        controller.checkClaude()
        Task { await AIService.shared.refreshCodexStatus() }
        #endif
    }

    @ViewBuilder private func content(_ p: SettingsRoute.Page, _ tab: SettingsRoute.Tab?) -> some View {
        switch p {
        case .general:
            if tab == .shortcuts {
                ShortcutsSettingsView()
            } else {
                GeneralSettingsTab(model: SettingsSections.general(state: state, controller: controller, open: { select($0) }))
            }
        case .agents:
            let built = SettingsSections.agents(state: state, controller: controller)
            AgentsSettingsPage(model: built.0, actions: built.1)
        case .chat:
            chat(tab)
        case .services:
            ServicesSettingsPage(cards: SettingsSections.services(state: state, controller: controller, drafts: drafts), text: drafts.text,
                                 dirty: drafts.isDirty, saved: drafts.isSaved, save: { controller.saveService($0, drafts: drafts) },
                                 toggle: SettingsSections.toggle(state: state))
        case .cat:
            CatSettingsSection(tab: tab ?? .look)
        case .devices:
            DevicesSettingsSection()
        }
    }

    @ViewBuilder private func chat(_ tab: SettingsRoute.Tab?) -> some View {
        switch tab ?? .yourAI {
        case .keys:
            KeysTab(cards: SettingsSections.keys(state: state, controller: controller, drafts: drafts), text: drafts.text, dirty: drafts.isDirty,
                    saved: drafts.isSaved, save: { controller.saveKey($0, drafts: drafts) }, remove: { controller.removeKey($0, drafts: drafts) },
                    toggle: SettingsSections.toggle(state: state))
        case .localModels:
            LocalModelsTab(model: SettingsSections.localModels(state: state, controller: controller), showAddServer: $controller.showAddServer,
                           rescan: { controller.rescan() }, remove: { controller.removeServer($0) }, toggle: SettingsSections.toggle(state: state),
                           addServer: { controller.addServer(name: $0, baseURL: $1, key: $2) })
        case .sidekick:
            SidekickSettingsSection()
        case .companion:
            CompanionTab(model: SettingsSections.companion(store: companionStore), setHumor: { v in companionStore.update { $0.humor = v } },
                         setSeeSessions: { v in companionStore.update { $0.seeSessions = v } },
                         deleteAll: { if companionStore.deleteAll() == 0 { ClaudeService.shared.forgetAllStored() } })
        default:
            YourAITab(model: SettingsSections.yourAI(state: state, controller: controller),
                      setChat: { controller.setChat($0) }, openKeys: { select(SettingsRoute.Place(page: .chat, tab: .keys)) })
        }
    }
}

// MARK: - Sidebar background (NSVisualEffectView .sidebar)

/// One line of result under the buttons of a box (Settings → Agents): small grey text as the box's other captions, red for a failure; the user can select it to copy a backup's name.
struct HookNoteLine: View {
    let note: HookNote
    var body: some View {
        Text(note.text)
            .font(.system(size: 11))
            .foregroundColor(note.ok ? .secondary : .red)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}

struct SidebarBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .sidebar
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Sidebar row (System Settings style icon)

struct SettingsSidebarRow: View {
    let title: String
    let icon: String
    let color: String

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color(hex: color)))
        }
    }
}

// MARK: - Integration filter row (reusable for Vercel / n8n)

struct IntegrationFilterRow: View {
    let label: String
    let items: [String]
    @Binding var filter: Set<String>
    let loading: Bool
    let onLoad: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            WrapRow {
                if loading {
                    ProgressView().scaleEffect(0.6)
                } else {
                    Button(items.isEmpty ? "Load list" : "Refresh") { onLoad() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                if !filter.isEmpty {
                    Button("Clear") { filter = [] }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .foregroundColor(.secondary)
                }
            }
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(items, id: \.self) { item in
                        Toggle(item, isOn: Binding(
                            get: { filter.isEmpty || filter.contains(item) },
                            set: { on in
                                if on { filter.insert(item) }
                                else  {
                                    if filter.isEmpty { filter = Set(items).subtracting([item]) }
                                    else { filter.remove(item) }
                                    if filter.count == items.count { filter = [] }
                                }
                            }
                        ))
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                        .toggleStyle(.checkbox)
                    }
                }
                .padding(.leading, 4)
                if !filter.isEmpty {
                    HelpText("Watching \(filter.count) of \(items.count)")
                }
            }
        }
    }
}

// MARK: - Shortcut recorder button

extension Notification.Name {
    /// A recorder started listening: the other recorders stop, so one key press is recorded once.
    static let shortcutRecordingStarted = Notification.Name("notchBuddy.shortcutRecordingStarted")
}

struct ShortcutRecorderButton: View {
    @Binding var flags: UInt
    @Binding var code: UInt16
    /// Runs once after a combination was recorded, when both bindings already hold it.
    var onRecorded: (() -> Void)? = nil
    @State private var isRecording = false
    @State private var token: Any?
    @State private var recorderID = UUID()

    var body: some View {
        Button {
            guard !isRecording else { return }
            NotificationCenter.default.post(name: .shortcutRecordingStarted, object: recorderID)
            isRecording = true
            token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let keyCode = event.keyCode
                let mods = event.modifierFlags.intersection([.command, .control, .option, .shift]).rawValue
                let consumed = MainActor.assumeIsolated { self.record(keyCode: keyCode, mods: mods) }
                return consumed ? nil : event
            }
        } label: {
            Text(isRecording ? "Press keys…" : shortcutLabel)
                .font(.system(size: 11, design: .monospaced))
                .padding(.horizontal, 8).padding(.vertical, 3)
                // One minimum width for every key cap, so the switches of the shortcut list line up: the widest label, ^⌥Space, is 47.6 pt, plus 16 pt of padding.
                .frame(minWidth: 64)
                .background(isRecording ? Color.accentColor.opacity(0.12) : Color(NSColor.controlBackgroundColor))
                .cornerRadius(5)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.gray.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onReceive(NotificationCenter.default.publisher(for: .shortcutRecordingStarted)) { note in
            if (note.object as? UUID) != recorderID { stopRecording() }
        }
        .onDisappear { stopRecording() }
    }

    /// A key press while recording. Returns true when the recorder took it. `ShortcutLogic.recorderKey` decides: ⎋
    /// cancels, a key without a modifier goes on to whoever wanted it, a combination that is not `isUsableGlobal`
    /// is refused with a beep.
    private func record(keyCode: UInt16, mods: UInt) -> Bool {
        switch ShortcutLogic.recorderKey(keyCode: keyCode, nsFlags: mods) {
        case .cancel:
            stopRecording()
            return true
        case .passThrough:
            return false
        case .refuse:
            NSSound.beep()
            return true
        case .record(let spec):
            flags = spec.nsFlags
            code = spec.keyCode
            stopRecording()
            onRecorded?()
            return true
        }
    }

    private func stopRecording() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
        isRecording = false
    }

    private var shortcutLabel: String {
        ShortcutLogic.displayString(for: ShortcutSpec(keyCode: code, nsFlags: flags),
                                    keyName: { KeyLayoutNames.name(for: $0) })
    }
}
