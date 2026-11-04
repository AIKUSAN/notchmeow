import SwiftUI
import ServiceManagement
import AppKit

// The app side of Settings → General, Agents, Services and Devices: the actions and the results the pages show. The bodies are today's SettingsView actions, moved (not rewritten):
// the same statements, `statusMessage` is `banner`, and the old @State reads are these @Published properties. Every install keeps its preview, "Confirm & write", backup and notes;
// nothing here writes a file without the user's Confirm. The pages take the models SettingsSections builds from this controller, so nothing in a page calls a store.

@MainActor
final class SettingsController: ObservableObject {
    private let state = AppState.shared

    /// The result line at the foot of the page (today's statusMessage). "❌" in front marks a failure.
    @Published var banner: String = ""
    /// What the last install or uninstall of Claude Code's hooks did, shown right under the buttons.
    @Published var claudeNote: HookNote?
    @Published var hookNeedsUpdate: Bool = HookServer.hooksNeedUpdate()
    /// The JSON preview of each kind waiting for Confirm & write (the new text an install would write).
    @Published var pending: [HookKind: String] = [:]
    @Published var launchAtStartup: Bool = (SMAppService.mainApp.status == .enabled)
    @Published var vercelProjects: [String] = []
    @Published var loadingVercel = false
    @Published var n8nWorkflows: [String] = []
    @Published var loadingN8n = false

    // The AI page (Your AI, Keys, Local models): today's SettingsView state, held here so the pages read a model.
    /// ✓ / ✗ after a pasted key was checked with a model-list call.
    @Published var keyWorks: [AIProviderID: Bool] = [:]
    /// The Anthropic model list from the API; empty until it is fetched (the fallback list is shown then).
    @Published var fetchedModels: [(id: String, label: String)] = []
    @Published var modelChoice: String
    @Published var customModel: String
    @Published var showAddServer = false
    @Published var rescanning = false
    @Published var checkingClaude = false

    /// Claude model — dynamic list fetched from the API, static fallback if unavailable.
    static let fallbackModels: [(id: String, label: String)] = [
        ("claude-sonnet-4-6",         "Claude Sonnet 4.6"),
        ("claude-sonnet-5-5",         "Claude Sonnet 5.5"),
        ("claude-opus-5-5",           "Claude Opus 5.5"),
        ("claude-haiku-4-5-20251001", "Claude Haiku 4.5"),
    ]
    static let customModelTag = "__custom__"

    init() {
        let m = state.claudeModel
        let isPreset = Self.fallbackModels.contains { $0.id == m }
        modelChoice = isPreset ? m : Self.customModelTag
        customModel = isPreset ? "" : m
    }

    #if !APPSTORE
    @Published var planNote: HookNote?
    @Published var showStatusLineDiff = false
    @Published var pendingStatusLineJSON = ""
    @Published var statusLinePendingInstall = true
    @Published var planTogglePending = false

    @Published var geminiInstalled: Bool = HookServer.geminiHooksInstalled()
    @Published var geminiPendingInstall = true

    @Published var agyInstalled: Bool = HookServer.agyHooksInstalled()
    @Published var agyPendingInstall = true

    @Published var codexInstalled: Bool = HookServer.codexHooksInstalled()
    @Published var codexPendingInstall = true
    #endif

    // MARK: - By kind (the pages' install, uninstall, confirm and cancel buttons)

    func install(_ k: HookKind) {
        switch k {
        case .claude:
            #if APPSTORE
            installHooksAppStore()
            #else
            installHooks()
            #endif
        #if !APPSTORE
        case .gemini: triggerGeminiPreview(install: true)
        case .antigravity: triggerAgyPreview(install: true)
        case .codex: triggerCodexPreview(install: true)
        #else
        case .gemini, .antigravity, .codex: break   // no such cards in the App Store build
        #endif
        }
    }

    func uninstall(_ k: HookKind) {
        switch k {
        case .claude:
            #if APPSTORE
            uninstallHooksAppStore()
            #else
            uninstallHooks()
            #endif
        #if !APPSTORE
        case .gemini: triggerGeminiPreview(install: false)
        case .antigravity: triggerAgyPreview(install: false)
        case .codex: triggerCodexPreview(install: false)
        #else
        case .gemini, .antigravity, .codex: break   // no such cards in the App Store build
        #endif
        }
    }

    func confirm(_ k: HookKind) {
        switch k {
        case .claude: confirmInstall()
        #if !APPSTORE
        case .gemini: confirmGeminiOp()
        case .antigravity: confirmAgyOp()
        case .codex: confirmCodexOp()
        #else
        case .gemini, .antigravity, .codex: break   // no such cards in the App Store build
        #endif
        }
    }

    /// Cancel: the preview goes, nothing is written (each kind's Cancel was this line).
    func cancel(_ k: HookKind) {
        pending[k] = nil
        dropPreviewPrompt()
    }

    /// Cancel left no preview to confirm: the banner that asks for one goes. A result line (a write, an error) is kept, and so is the prompt while another preview waits.
    private func dropPreviewPrompt() {
        var relayWaits = false   // the plan relay's preview exists only in the build with the Plan usage card
        #if !APPSTORE
        relayWaits = showStatusLineDiff
        #endif
        if banner == "Review the JSON below before confirming." && pending.isEmpty && !relayWaits { banner = "" }
    }

    // MARK: - Claude Code hooks

    func installHooks() {
        do {
            pending[.claude] = try HookServer.shared.previewClaudeHooks()
            claudeNote = nil
            banner = "Review the JSON below before confirming."
        } catch {
            claudeNote = HookInstallNote.failure(error)
            banner = claudeNote?.text ?? ""
        }
    }

    func confirmInstall() {
        do {
            let backup = try HookServer.shared.writeClaudeHooks()
            pending[.claude] = nil
            hookNeedsUpdate = false
            claudeNote = HookInstallNote.installed("Hooks installed", file: "~/.claude/settings.json", backup: backup)
        } catch {
            claudeNote = HookInstallNote.failure(error)
        }
        banner = claudeNote?.text ?? ""
    }

    func uninstallHooks() {
        do {
            let removed = try HookServer.shared.uninstallClaudeHooks()
            if removed { hookNeedsUpdate = false }
            claudeNote = removed ? HookInstallNote.removed("Hooks", file: "~/.claude/settings.json")
                                 : HookInstallNote.absent("NotchMeow hooks", file: "~/.claude/settings.json")
        } catch {
            claudeNote = HookInstallNote.failure(error)
        }
        banner = claudeNote?.text ?? ""
    }

    #if APPSTORE
    /// App Store: the folder comes from an open panel (a security-scoped bookmark); nothing is read before the user picks it.
    func pickClaudeFolder(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.message = "Select your .claude folder (press ⇧⌘. to show hidden files)"
        panel.prompt = prompt
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        let realHomePath = getpwuid(getuid()).flatMap { String(cString: $0.pointee.pw_dir, encoding: .utf8) }
            ?? "/Users/\(NSUserName())"
        panel.directoryURL = URL(fileURLWithPath: realHomePath)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard url.lastPathComponent == ".claude" else {
            banner = "❌ Select the .claude folder (hidden, in your Home directory)."
            return nil
        }
        return url
    }

    func installHooksAppStore() {
        guard let claudeURL = pickClaudeFolder(prompt: "Select") else { return }
        let alert = NSAlert()
        alert.messageText = "Install NotchMeow hooks in ~/.claude?"
        alert.informativeText = "Will write:\n• ~/.claude/notchmeow/nm-hook\n• ~/.claude/settings.json (backup created first)"
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .informational
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try HookServer.shared.installAndWriteClaudeHooksAppStore(claudeURL: claudeURL)
            hookNeedsUpdate = false
            banner = "✓ Hooks installed — restart VS Code to activate."
        } catch {
            banner = "❌ \(error.localizedDescription)"
        }
    }

    func uninstallHooksAppStore() {
        guard let claudeURL = pickClaudeFolder(prompt: "Select") else { return }
        do {
            try HookServer.shared.uninstallClaudeHooksAppStore(claudeURL: claudeURL)
            banner = "✓ Hooks removed."
        } catch {
            banner = "❌ \(error.localizedDescription)"
        }
    }
    #endif

    // MARK: - Gemini CLI, Antigravity and Codex hooks (GitHub build)

    #if !APPSTORE
    func triggerGeminiPreview(install: Bool) {
        do {
            geminiPendingInstall = install
            pending[.gemini] = try HookServer.shared.previewGeminiHooks(install: install)
            banner = "Review the JSON below before confirming."
        } catch let e as NSError where e.domain == "NotchMeowNoop" {
            banner = e.localizedDescription
        } catch {
            banner = "❌ \(error.localizedDescription)"
        }
    }

    func confirmGeminiOp() {
        do {
            try HookServer.shared.writeGeminiHooks()
            pending[.gemini] = nil
            geminiInstalled = geminiPendingInstall
            banner = geminiPendingInstall
                ? "✓ Gemini CLI hooks installed in \(HookKind.gemini.hooksFile)"
                : "✓ Gemini CLI hooks removed."
        } catch {
            banner = "❌ \(error.localizedDescription)"
        }
    }

    func triggerAgyPreview(install: Bool) {
        do {
            agyPendingInstall = install
            pending[.antigravity] = try HookServer.shared.previewAgyHooks(install: install)
            banner = "Review the JSON below before confirming."
        } catch let e as NSError where e.domain == "NotchMeowNoop" {
            banner = e.localizedDescription
        } catch {
            banner = "❌ \(error.localizedDescription)"
        }
    }

    func confirmAgyOp() {
        do {
            try HookServer.shared.writeAgyHooks()
            pending[.antigravity] = nil
            agyInstalled = agyPendingInstall
            banner = agyPendingInstall
                ? "✓ Antigravity hooks installed in \(HookKind.antigravity.hooksFile)"
                : "✓ Antigravity hooks removed."
        } catch {
            banner = "❌ \(error.localizedDescription)"
        }
    }

    func triggerCodexPreview(install: Bool) {
        do {
            codexPendingInstall = install
            pending[.codex] = try HookServer.shared.previewCodexHooks(install: install)
            banner = "Review the JSON below before confirming."
        } catch let e as NSError where e.domain == "NotchMeowNoop" {
            banner = e.localizedDescription
        } catch {
            banner = "❌ \(error.localizedDescription)"
        }
    }

    func confirmCodexOp() {
        do {
            try HookServer.shared.writeCodexHooks()
            pending[.codex] = nil
            codexInstalled = codexPendingInstall
            banner = codexPendingInstall
                ? "✓ Codex hooks installed — run /hooks in Codex or open Hooks in the app's settings to trust them."
                : "✓ Codex hooks removed."
        } catch {
            banner = "❌ \(error.localizedDescription)"
        }
    }

    // MARK: - Plan usage (the status line relay, GitHub build)

    /// The switch "Show in the notch": on a relay that is installed it turns the gauge on; otherwise it installs the relay first (the gauge follows the confirm).
    func setShowPlan(_ on: Bool) {
        if on {
            if state.planRelayInstalled {
                state.showPlanInNotch = true
            } else {
                installRelay()
            }
        } else {
            state.showPlanInNotch = false
            planTogglePending = false
        }
    }

    func installRelay() {
        planTogglePending = true   // the relay is only for the notch's gauge: once confirmed it turns "Show in the notch" on
        installStatusLine()
    }

    func uninstallRelay() {
        uninstallStatusLine()
    }

    func cancelRelay() {
        pendingStatusLineJSON = ""
        showStatusLineDiff = false
        planTogglePending = false
        dropPreviewPrompt()
    }

    func installStatusLine() {
        do {
            pendingStatusLineJSON = try HookServer.shared.previewStatusLine(install: true)
            showStatusLineDiff = true
            statusLinePendingInstall = true
            planNote = nil
            banner = "Review the JSON below before confirming."
        } catch {
            // A failed preview leaves nothing to confirm: an older one can never be written.
            pendingStatusLineJSON = ""
            showStatusLineDiff = false
            planTogglePending = false
            planNote = HookInstallNote.failure(error)
            banner = planNote?.text ?? ""
        }
    }

    func uninstallStatusLine() {
        do {
            pendingStatusLineJSON = try HookServer.shared.previewStatusLine(install: false)
            showStatusLineDiff = true
            statusLinePendingInstall = false
            planNote = nil
            banner = "Review the JSON below before confirming."
        } catch {
            planNote = HookInstallNote.failure(error)
            banner = planNote?.text ?? ""
        }
    }

    func confirmStatusLine() {
        do {
            let backup = try HookServer.shared.writeStatusLine()
            showStatusLineDiff = false
            pendingStatusLineJSON = ""
            state.refreshPlanRelayState()
            if planTogglePending {
                state.showPlanInNotch = true
                planTogglePending = false
            }
            if !statusLinePendingInstall {
                state.showPlanInNotch = false
            }
            planNote = statusLinePendingInstall
                ? HookInstallNote.installed("Status line relay installed", file: "~/.claude/settings.json", backup: backup)
                : HookInstallNote.installed("Status line relay removed", file: "~/.claude/settings.json", backup: backup)
        } catch {
            planTogglePending = false
            planNote = HookInstallNote.failure(error)
        }
        banner = planNote?.text ?? ""
    }
    #endif

    // MARK: - Services

    /// Saves one card's fields and nothing else: each field through the Keychain (empty removes it), then the draft is marked saved with what was written.
    func saveService(_ pillId: String, drafts: SettingsDrafts) {
        guard let fields = SettingsMap.serviceFields[pillId] else { return }
        var failure: String?
        for id in fields {
            let value = drafts.book.text(id)
            if id == "github-token" {
                // Detect GitHub token changes before writing
                let prevGithubToken = KeychainStore.shared.get("github-token")
                guard saveKey("github-token", value: value) else { failure = Self.keychainBanner(value); continue }
                let nextGithubToken = KeychainStore.shared.get("github-token")
                if nextGithubToken != prevGithubToken {
                    state.githubPulse = nil
                    state.githubActivity = nil
                    if nextGithubToken == nil { state.githubStats = nil }
                    if nextGithubToken != nil {
                        GithubPoller.shared.triggerPulseNow()
                        GithubPoller.shared.refreshActivityIfStale()
                    }
                }
            } else {
                guard saveKey(id, value: value) else { failure = Self.keychainBanner(value); continue }
            }
            drafts.markSaved(id, stored: value)
        }
        banner = failure ?? "✓ \(PillCatalog.all.first { $0.id == pillId }?.name ?? "") saved."
    }

    /// The banner for a Keychain write or removal the Keychain refused: an empty value was a removal.
    private static func keychainBanner(_ value: String) -> String {
        value.isEmpty ? "❌ Couldn't remove from the Keychain." : "❌ Couldn't save to the Keychain."
    }

    /// Writes one Keychain field (an empty value removes it). False when the Keychain refused the write or the removal.
    private func saveKey(_ key: String, value: String) -> Bool {
        if value.isEmpty { return KeychainStore.shared.remove(key) }
        return KeychainStore.shared.set(key, value: value)
    }

    // MARK: - Vercel project list

    func loadVercelProjects() {
        guard let token = KeychainStore.shared.get("vercel-token") else {
            banner = "❌ Save Vercel token first."
            return
        }
        loadingVercel = true
        guard let url = URL(string: "https://api.vercel.com/v9/projects?limit=100") else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            let names: [String]
            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let projects = json["projects"] as? [[String: Any]] {
                names = projects.compactMap { $0["name"] as? String }.sorted()
            } else {
                names = []
            }
            Task { @MainActor in
                self?.vercelProjects = names
                self?.loadingVercel = false
                if names.isEmpty { self?.banner = "❌ No Vercel projects found." }
            }
        }.resume()
    }

    // MARK: - n8n workflow list

    func loadN8nWorkflows() {
        guard let apiKey  = KeychainStore.shared.get("n8n-api-key"),
              let rawBase = KeychainStore.shared.get("n8n-url") else {
            banner = "❌ Save n8n URL and API key first."
            return
        }
        loadingN8n = true
        let base = rawBase.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urls = ["\(base)/api/v1/workflows?limit=100", "\(base)/rest/workflows?limit=100"]
        fetchN8nWorkflows(urls: urls, apiKey: apiKey, idx: 0)
    }

    func fetchN8nWorkflows(urls: [String], apiKey: String, idx: Int) {
        guard idx < urls.count, let url = URL(string: urls[idx]) else {
            loadingN8n = false
            banner = "❌ No n8n workflows found."
            return
        }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue(apiKey, forHTTPHeaderField: "X-N8N-API-KEY")
        URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let data, code == 200 else {
                Task { @MainActor in self?.fetchN8nWorkflows(urls: urls, apiKey: apiKey, idx: idx + 1) }
                return
            }
            let items: [[String: Any]]
            if let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               let arr = obj["data"] as? [[String: Any]] { items = arr }
            else if let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] { items = arr }
            else { items = [] }
            let names = items.compactMap { $0["name"] as? String }.sorted()
            Task { @MainActor in
                self?.n8nWorkflows = names
                self?.loadingN8n = false
                if names.isEmpty { self?.banner = "❌ No n8n workflows found." }
            }
        }.resume()
    }

    // MARK: - AI and chat (Your AI, Keys, Local models, the Claude plan)

    /// Saves one provider's key, then checks it with a model-list call (today's SettingsView.saveKey). The draft's trimmed text is what is stored and what the field shows after.
    /// It no longer sets the preferred cloud: that went with the second Anthropic box.
    func saveKey(_ provider: AIProviderID, drafts: SettingsDrafts) {
        guard let fieldId = AICatalog.info(provider).keychainKey else { return }
        let key = drafts.book.text(fieldId).trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            guard KeychainStore.shared.remove(fieldId) else {
                banner = "❌ Couldn't remove from the Keychain."
                return
            }
        } else if !KeychainStore.shared.set(fieldId, value: key) {
            banner = "❌ Couldn't save to the Keychain."
            return
        }
        drafts.markSaved(fieldId, stored: key)
        state.fetchedProviderModels[provider] = nil
        keyWorks[provider] = nil
        if provider == .anthropic {
            // The model list is the Anthropic key's: a changed or removed key never leaves its models on the picker.
            fetchedModels = []
            fetchModelsIfNeeded()
        }
        guard !key.isEmpty else { banner = "Key removed."; return }
        banner = "Checking the key…"
        Task {
            let result = await AIService.shared.listCloudModels(provider, key: key)
            if !result.models.isEmpty {
                keyWorks[provider] = true
                banner = "✓ Key saved and working."
                return
            }
            // Only an auth failure is a rejected key (red mark); offline and the rest leave the mark off.
            let failure = AIMessages.listFailure(result.failure, provider: provider, online: state.isOnline)
            keyWorks[provider] = failure.rejected ? false : nil
            banner = failure.rejected ? "❌ \(failure.text)" : failure.text
        }
    }

    /// Removes one provider's key: the same path with an empty value.
    func removeKey(_ provider: AIProviderID, drafts: SettingsDrafts) {
        guard let fieldId = AICatalog.info(provider).keychainKey else { return }
        drafts.text(fieldId).wrappedValue = ""
        saveKey(provider, drafts: drafts)
    }

    /// Today's model fetch, when the AI page opens: the Anthropic model list, if a key is saved.
    func fetchModelsIfNeeded() {
        guard fetchedModels.isEmpty,
              let key = KeychainStore.shared.get("anthropic-api-key"), !key.isEmpty else { return }
        Task {
            let models = await ClaudeService.fetchModels(apiKey: key)
            guard !models.isEmpty else { return }
            fetchedModels = models
            let m = state.claudeModel
            if models.contains(where: { $0.id == m }) {
                modelChoice = m
                customModel = ""
            } else if modelChoice != Self.customModelTag {
                modelChoice = Self.customModelTag
                customModel = m
            }
        }
    }

    /// The Anthropic model pop-up: a preset becomes the Claude model; Custom… applies the typed id (today's onChange).
    func chooseModel(_ choice: String) {
        modelChoice = choice
        if choice != Self.customModelTag { state.claudeModel = choice } else { applyCustomModel(customModel) }
    }

    /// The custom model field: every edit applies (today's onChange of the field).
    func typeCustomModel(_ value: String) {
        customModel = value
        applyCustomModel(value)
    }

    func applyCustomModel(_ value: String) {
        let id = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !id.isEmpty { state.claudeModel = id }
    }

    /// Removes a server the user added: its key, its entry, and any choice that named it goes back to Auto.
    func removeServer(_ id: String) {
        guard let server = state.customServers.first(where: { $0.id == id }) else { return }
        // The server stays listed while its key is still in the Keychain: a refused removal is said, not hidden.
        guard KeychainStore.shared.remove(server.keychainAccount) else {
            banner = "❌ Couldn't remove from the Keychain."
            return
        }
        state.customServers.removeAll { $0.id == id }
        state.localServers.removeAll { $0.serverID == id }
        if case .explicit(let ref) = state.choice(for: .chat), ref.serverID == id { state.setChoice(.auto, for: .chat) }
        if case .explicit(let ref) = state.choice(for: .files), ref.serverID == id { state.setChoice(.auto, for: .files) }
    }

    /// The Add server sheet's one action (today's closure): a new custom server, its key in the Keychain, then a discovery.
    func addServer(name: String, baseURL: String, key: String?) {
        let server = CustomServer(id: CustomServer.newID(), name: name, baseURL: baseURL)
        if let key, !key.isEmpty, !KeychainStore.shared.set(server.keychainAccount, value: key) {
            banner = "❌ Couldn't save to the Keychain."
            return
        }
        state.customServers.append(server)
        Task { await AIService.shared.discover() }
    }

    /// Rescan: one discovery pass, the button says Scanning… until it ends.
    func rescan() {
        rescanning = true
        Task {
            await AIService.shared.discover()
            rescanning = false
        }
    }

    #if !APPSTORE
    /// "Use my Claude plan": the plan may answer, Auto prefers it (today's ConnectClaudePlanView.startUsing).
    func connectClaude() {
        state.claudeCodeEnabled = true
        state.preferredCloud = .claudeCode
        state.setChoice(.auto, for: .chat)
    }

    /// "Stop using it" (today's stopUsing).
    func stopClaude() {
        state.claudeCodeEnabled = false
        if state.preferredCloud == .claudeCode { state.preferredCloud = .anthropic }
        state.setChoice(SettingsAI.afterStoppingClaude(state.choice(for: .chat)), for: .chat)
        state.setChoice(SettingsAI.afterStoppingClaude(state.choice(for: .files)), for: .files)
    }

    /// "Check again": asks Claude Code its version and sign-in once more (today's refresh), never on a timer.
    func checkClaude() {
        checkingClaude = true
        Task {
            await AIService.shared.refreshClaudeStatus()
            checkingClaude = false
        }
    }
    #endif

    /// Make main: the chat's choice becomes this setting. Only Chat changes; File questions keeps its own.
    func setChat(_ setting: FeatureSetting) {
        state.setChoice(setting, for: .chat)
    }

    // MARK: - General, Devices

    /// Registers or unregisters the app at login. On failure the switch goes back (the page's binding sets the value first).
    func toggleStartup(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else  { try SMAppService.mainApp.unregister() }
        } catch {
            banner = "❌ Startup: \(error.localizedDescription)"
            launchAtStartup = !on
        }
    }

    /// Shows the file a row names in Finder: the hook script for Claude Code, the settings file for the others (`~` expanded).
    func reveal(_ k: HookKind) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: (k.hooksFile as NSString).expandingTildeInPath)])
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

extension HookKind {
    /// The file a kind's hooks live in: the card names it, Reveal opens it, the install banners name it. Claude Code's is the hook script.
    var hooksFile: String {
        switch self {
        case .claude: return HookServer.hookScriptPath
        case .gemini: return "~/.gemini/settings.json"
        case .antigravity: return "~/.gemini/config/hooks.json"
        case .codex: return "~/.codex/hooks.json"
        }
    }
}
