import SwiftUI

// The models the Settings pages take, built from AppState, the controller and the drafts (the restyle plan's Task 10). One builder per page or per row kind; every pill row
// comes from `pills(state:ids:)`, so the four-slot cap, the chips and the App Store filter (PillCatalog.available) are the same everywhere. The pages stay plain: nothing here draws.
// Bindings to AppState use the observed wrapper (`@ObservedObject var state = state`), which projects `$state.x` as a Binding without a view.

enum SettingsSections {
    /// The one toggle of a pill (the change itself is AppState's; the four-slot cap is shown by the switch's state).
    @MainActor
    static func toggle(state: AppState) -> (String) -> Void {
        { id in state.toggleIntegration(id) }
    }

    // MARK: - General

    @MainActor
    static func general(state: AppState, controller: SettingsController, open: @escaping (SettingsRoute.Place) -> Void) -> GeneralSettingsModel {
        @ObservedObject var state = state
        let active = PillCatalog.available.filter { state.activeIntegrations.contains($0.id) }
        return GeneralSettingsModel(
            soundEnabled: $state.soundEnabled,
            soundVolume: $state.soundVolume,
            openOnHover: $state.openOnHover,
            focusAware: $state.focusAware,
            hoverGlow: $state.hoverGlow,
            tuckAway: $state.tuckAway,
            closeAfter: $state.autoCloseInterval,
            mainPill: Binding(get: { state.mainPillId }, set: { id in
                state.mainPillId = id
                state.activeIntegrations.remove(id)
                state.loadIntegrationTasks()
                state.setFocus(id)
            }),
            mainChoices: PillCatalog.available.filter { $0.category == .workspace && !$0.comingSoon }.map { (id: $0.id, name: $0.name) },
            slots: SettingsStatus.slots(active: state.activeIntegrations, catalog: PillCatalog.available.map { (id: $0.id, name: $0.name) }),
            slotLinks: active.map { (name: $0.name, place: SettingsMap.pillHome($0.id)) },
            launchAtStartup: Binding(get: { controller.launchAtStartup }, set: { on in
                controller.launchAtStartup = on
                controller.toggleStartup(on)
            }),
            open: open)
    }

    // MARK: - Pill rows (Agents, AI keys, Local models, Services)

    /// The rows for the given pill ids, in that order; an id the build does not offer (PillCatalog.available) is left out.
    @MainActor
    static func pills(state: AppState, ids: [String]) -> [PillSwitchModel] {
        ids.compactMap { id in
            guard let def = PillCatalog.available.first(where: { $0.id == id }) else { return nil }
            let isOn = state.activeIntegrations.contains(id)
            let switchState = SettingsStatus.pillSwitch(isOn: isOn, isMain: id == state.mainPillId,
                                                        activeCount: state.activeIntegrations.count, missing: missing(def, state: state))
            return PillSwitchModel(id: id, name: def.name, color: def.color, isOn: isOn, state: switchState)
        }
    }

    /// The words a pill's missing prerequisite gives (today's pill rows). A missing prerequisite never disables a switch (rule 10); only the cap does.
    @MainActor
    private static func missing(_ def: PillDefinition, state: AppState) -> String? {
        if def.comingSoon { return "Coming soon" }
        #if !APPSTORE
        switch def.id {
        case "integration_claude": if !HookServer.claudeHooksInstalled() { return "Hooks not installed" }
        case "agent_gemini": if !HookServer.geminiHooksInstalled() { return "Hooks not installed" }
        case "agent_antigravity": if !HookServer.agyHooksInstalled() { return "Hooks not installed" }
        case "agent_codex": if !HookServer.codexHooksInstalled() { return "Hooks not installed" }
        default: break
        }
        #endif
        if def.category == .ai {
            if let provider = ChatProvider(pillID: def.id), provider.isLocal {
                if !state.localServers.contains(where: { $0.serverID == provider.rawValue && $0.isReady }) { return "Not connected" }
            } else {
                let keyId = def.id == "ai_anthropic" ? "anthropic-api-key"
                    : def.id == "ai_google" ? "google-api-key" : "openai-api-key"
                if KeychainStore.shared.get(keyId) == nil { return "Key not configured" }
            }
        }
        return nil
    }

    // MARK: - Agents

    @MainActor
    static func agents(state: AppState, controller: SettingsController) -> (AgentsSettingsModel, AgentsSettingsActions) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let model = AgentsSettingsModel(
            pills: pills(state: state, ids: ["integration_claude", "agent_cursor", "agent_antigravity", "agent_codex", "agent_gemini"]),
            hooks: hookCards(controller: controller, home: home),
            plan: planCard(state: state, controller: controller),
            home: home)
        #if APPSTORE
        // The App Store build has no Plan usage card, so its relay actions have nothing to run.
        let relay = (setShowPlan: { (_: Bool) in }, installRelay: { }, uninstallRelay: { }, confirmRelay: { }, cancelRelay: { })
        #else
        let relay = (setShowPlan: { (on: Bool) in controller.setShowPlan(on) }, installRelay: { controller.installRelay() },
                     uninstallRelay: { controller.uninstallRelay() }, confirmRelay: { controller.confirmStatusLine() },
                     cancelRelay: { controller.cancelRelay() })
        #endif
        let actions = AgentsSettingsActions(
            toggle: toggle(state: state),
            install: { controller.install($0) },
            uninstall: { controller.uninstall($0) },
            confirm: { controller.confirm($0) },
            cancel: { controller.cancel($0) },
            setShowPlan: relay.setShowPlan,
            installRelay: relay.installRelay,
            uninstallRelay: relay.uninstallRelay,
            confirmRelay: relay.confirmRelay,
            cancelRelay: relay.cancelRelay,
            copy: { controller.copy($0) },
            reveal: { controller.reveal($0) })
        return (model, actions)
    }

    @MainActor
    private static func hookCards(controller: SettingsController, home: String) -> [HookCardModel] {
        #if APPSTORE
        let claudeInstalled: Bool? = nil
        let claudePath = "~/.claude/notchmeow/nm-hook"
        let claudeRevealable = false
        #else
        let claudeInstalled: Bool? = HookServer.claudeHooksInstalled()
        let claudePath = SettingsLayout.displayPath(HookKind.claude.hooksFile, home: home)
        let claudeRevealable = true
        #endif
        var cards = [
            HookCardModel(
                kind: .claude, title: "Claude Code hooks",
                chip: SettingsStatus.hookChip(installed: claudeInstalled, needsUpdate: controller.hookNeedsUpdate),
                next: controller.hookNeedsUpdate ? "Hooks outdated — update them to answer Claude's questions from the notch" : nil,
                path: claudePath, revealable: claudeRevealable, note: controller.claudeNote,
                pendingJSON: controller.pending[.claude], needsUpdate: controller.hookNeedsUpdate, installed: claudeInstalled),
        ]
        #if !APPSTORE
        cards += [
            hookCard(.gemini, "Gemini CLI hooks", installed: controller.geminiInstalled, path: HookKind.gemini.hooksFile,
                     next: "Restart Gemini CLI to activate", controller: controller),
            hookCard(.antigravity, "Antigravity hooks", installed: controller.agyInstalled, path: HookKind.antigravity.hooksFile,
                     next: "Restart Antigravity to activate", controller: controller),
            hookCard(.codex, "Codex hooks", installed: controller.codexInstalled, path: HookKind.codex.hooksFile,
                     next: "Open Codex, run /hooks or open Hooks in the app's settings, and trust them", controller: controller),
        ]
        #endif
        return cards
    }

    #if !APPSTORE
    @MainActor
    private static func hookCard(_ kind: HookKind, _ title: String, installed: Bool, path: String, next: String, controller: SettingsController) -> HookCardModel {
        HookCardModel(kind: kind, title: title, chip: SettingsStatus.hookChip(installed: installed, needsUpdate: false),
                      next: installed ? next : nil, path: path, revealable: true, note: nil,
                      pendingJSON: controller.pending[kind], needsUpdate: false, installed: installed)
    }
    #endif

    @MainActor
    private static func planCard(state: AppState, controller: SettingsController) -> PlanUsageModel? {
        #if APPSTORE
        return nil
        #else
        return PlanUsageModel(
            showInNotch: state.showPlanInNotch, relayInstalled: state.planRelayInstalled, note: controller.planNote,
            heard: ClaudePlanGauge.statusNote(relayInstalled: state.planRelayInstalled, usage: state.claudePlanUsage),
            pendingJSON: controller.showStatusLineDiff ? controller.pendingStatusLineJSON : nil)
        #endif
    }

    // MARK: - Companion

    /// Settings → AI and chat → Companion: the store's settings and conversation count, the chat's brain by its label, and the lines the last request sent (memory only).
    @MainActor
    static func companion(store: CompanionStore) -> CompanionTab.Model {
        CompanionTab.Model(humor: store.settings.humor, seeSessions: store.settings.seeSessions, brain: AIService.shared.chip(.chat).label,
                           conversations: store.conversations.count, lastSent: Companion.shared.lastSent)
    }

    // MARK: - Services

    /// The service cards in the spec's order, each one offered by the build (PillCatalog.available: Music is GitHub-only). The chip is "Not saved" while a field's draft
    /// differs from what is stored, else Saved or No key yet (n8n: both fields saved).
    @MainActor
    static func services(state: AppState, controller: SettingsController, drafts: SettingsDrafts) -> [ServiceCardModel] {
        @ObservedObject var state = state
        func card(_ id: String, _ name: String, _ color: String, fields: [ServiceFieldModel], saved: Bool,
                  help: String? = nil, filter: ServiceFilterModel? = nil) -> ServiceCardModel? {
            guard let pill = pills(state: state, ids: [id]).first else { return nil }
            let chip: String? = fields.isEmpty ? nil
                : fields.contains { drafts.isDirty($0.id) } ? "Not saved"
                : SettingsStatus.serviceChip(saved: saved)
            return ServiceCardModel(id: id, name: name, color: color, chip: chip, pill: pill, fields: fields, help: help, filter: filter)
        }
        func field(_ id: String, _ placeholder: String, secure: Bool = true) -> ServiceFieldModel {
            ServiceFieldModel(id: id, placeholder: placeholder, secure: secure)
        }
        let n8nFilter = ServiceFilterModel(label: "Workflows", items: controller.n8nWorkflows, filter: $state.n8nWorkflowFilter,
                                           loading: controller.loadingN8n, onLoad: controller.loadN8nWorkflows)
        let vercelFilter = ServiceFilterModel(label: "Projects", items: controller.vercelProjects, filter: $state.vercelProjectFilter,
                                              loading: controller.loadingVercel, onLoad: controller.loadVercelProjects)
        return [
            card("integration_resend", "Resend", "#22C55E",
                 fields: [field("resend-api-key", "API key  (re_…)"), field("resend-from", "From address  (you@yourdomain.com)", secure: false)],
                 saved: drafts.isSaved("resend-api-key")),
            card("integration_n8n", "n8n", "#F29B38",
                 fields: [field("n8n-url", "Instance URL  (https://…)", secure: false), field("n8n-api-key", "API key")],
                 saved: drafts.isSaved("n8n-url") && drafts.isSaved("n8n-api-key"), filter: n8nFilter),
            card("integration_vercel", "Vercel", "#7C5CFF", fields: [field("vercel-token", "Token")],
                 saved: drafts.isSaved("vercel-token"), filter: vercelFilter),
            card("integration_github", "GitHub", "#F4505E", fields: [field("github-token", "Personal Access Token")],
                 saved: drafts.isSaved("github-token"),
                 help: "Classic token with repo scope, or fine-grained with read access to Pull requests, Commit statuses and Actions."),
            card("integration_stripe", "Stripe", "#0570DE", fields: [field("stripe-api-key", "Secret key  (sk_live_… or sk_test_…)")],
                 saved: drafts.isSaved("stripe-api-key")),
            card("integration_calcom", "Cal.com", "#C9956A", fields: [field("calcom-api-key", "API key  (cal_live_…)")],
                 saved: drafts.isSaved("calcom-api-key")),
            card("integration_notion", "Notion", "#E8E8E8", fields: [field("notion-api-key", "Integration token  (secret_…)")],
                 saved: drafts.isSaved("notion-api-key")),
            card("integration_music", "Music", "#FA2D48", fields: [], saved: false,
                 help: "Shows what Apple Music or Spotify is playing. Nothing to enter."),
        ].compactMap { $0 }
    }

    // MARK: - AI and chat (Your AI, Keys, Local models)

    /// Your AI: the two features (Chat, File questions) with their pop-ups, the cloud preference, the rows that make one the main choice, and the Claude plan's details.
    @MainActor
    static func yourAI(state: AppState, controller: SettingsController) -> YourAIModel {
        @ObservedObject var state = state
        let input = aiInput(state: state)
        let features = AIFeature.allCases.map { feature in
            AIFeatureRow(id: feature, label: feature == .chat ? "Chat" : "File questions",
                         selection: Binding(get: { state.choice(for: feature) }, set: { state.setChoice($0, for: feature) }),
                         sections: choiceSections(state: state, feature: feature),
                         resolution: AIService.shared.resolutionLine(feature))
        }
        let ready = AIService.shared.cloudKeys
        var choices: [(id: AIProviderID, label: String)] = []
        if ready.contains(.claudeCode) { choices.append((id: .claudeCode, label: "Claude plan")) }
        if ready.contains(.anthropic) { choices.append((id: .anthropic, label: ready.contains(.claudeCode) ? "Claude API" : "Claude")) }
        if ready.contains(.openai) { choices.append((id: .openai, label: "OpenAI")) }
        let prefer: AIPreferModel? = ready.intersection([.claudeCode, .anthropic, .openai]).count >= 2
            ? AIPreferModel(selection: $state.preferredCloud, choices: choices) : nil
        let rows: [AIRowModel] = SettingsAI.rows(input).map { row in
            var addKey = false
            if case .key(let p) = row { addKey = !input.keys.contains(p) }
            return AIRowModel(id: row, title: SettingsAI.title(row, input), line: SettingsAI.helpLine(row, input),
                              chip: SettingsAI.chip(row, input), isMain: SettingsAI.isMain(row, chat: state.choice(for: .chat)),
                              makeMain: SettingsAI.makeMain(row, input), addKey: addKey, reason: SettingsAI.reasonLine(row, input))
        }
        #if !APPSTORE
        let claude: ClaudePlanDetails? = ClaudePlanDetails(
            state: input.claudeState, note: ClaudeCodeEngine.note, line: claudeLine(state.claudeCodeStatus),
            inUse: state.claudeCodeEnabled && state.preferredCloud == .claudeCode,
            checking: controller.checkingClaude, model: $state.claudeCodeModel,
            connect: { controller.connectClaude() }, stop: { controller.stopClaude() }, checkAgain: { controller.checkClaude() },
            signIn: { ClaudeCodeActions.signIn() }, guide: URL(string: ClaudeCodeLocator.installGuide))
        #else
        let claude: ClaudePlanDetails? = nil
        #endif
        return YourAIModel(features: features, prefer: prefer, rows: rows, claude: claude)
    }

    /// Keys: one card per provider, in Keys' order. Each card's switch is its provider's pill; Anthropic also has the model pop-up and its Custom… field.
    @MainActor
    static func keys(state: AppState, controller: SettingsController, drafts: SettingsDrafts) -> [KeyCardModel] {
        let cards: [(provider: AIProviderID, name: String, help: String, placeholder: String, pillId: String)] = [
            (.anthropic, "Anthropic", "From the Claude Console. Saved in the Keychain, checked when you save.", "API key (sk-ant-…)", "ai_anthropic"),
            (.google, "Google AI", "From Google AI Studio. Saved in the Keychain, checked when you save.", "API key (AI Studio)", "ai_google"),
            (.openai, "OpenAI", "From the OpenAI dashboard. Saved in the Keychain, checked when you save.", "API key (sk-…)", "ai_openai"),
        ]
        let options = controller.fetchedModels.isEmpty ? SettingsController.fallbackModels : controller.fetchedModels
        return cards.map { card in
            KeyCardModel(
                provider: card.provider, name: card.name, color: ChatProvider(card.provider).accentHex, help: card.help,
                fieldId: AICatalog.info(card.provider).keychainKey!, placeholder: card.placeholder,
                works: controller.keyWorks[card.provider], pill: pills(state: state, ids: [card.pillId]).first,
                anthropicModel: card.provider == .anthropic ? AnthropicModelPicker(
                    choice: Binding(get: { controller.modelChoice }, set: { controller.chooseModel($0) }),
                    options: options, customTag: SettingsController.customModelTag,
                    custom: Binding(get: { controller.customModel }, set: { controller.typeCustomModel($0) })) : nil)
        }
    }

    /// The island switch of a local server, by its provider (not its name): a renamed or network LM Studio still gets its switch.
    private static let localPillIds: [AIProviderID: String] = [.ollama: "ai_ollama", .lmstudio: "ai_lmstudio"]

    /// Local models: each server on this Mac or on the network, with its chip, its get or update link, Remove for one the user added, its island switch and, when it has
    /// no model yet, the reason the chat cannot use it (makeMain's words). Apple on-device is the last line.
    @MainActor
    static func localModels(state: AppState, controller: SettingsController) -> LocalModelsModel {
        let input = aiInput(state: state)
        var rows: [ServerRowModel] = []
        for server in state.localServers {
            var note: String?
            // A server that is not installed shows only its Get link; the words about starting it are for an installed one.
            if case .unavailable(let reason) = SettingsAI.makeMain(.server(server.serverID), input), server.status != .notInstalled { note = reason }
            rows.append(ServerRowModel(
                id: server.serverID, name: server.name, chip: SettingsAI.serverChip(server.status), ready: server.isReady,
                network: networkNote(server), getLink: getLink(server), removable: server.serverID.hasPrefix(CustomServer.idPrefix),
                pill: localPillIds[server.provider].flatMap { pills(state: state, ids: [$0]).first }, note: note))
        }
        return LocalModelsModel(servers: rows, apple: state.appleStatus.line, rescanning: controller.rescanning)
    }

    /// The inputs the rows read, from AppState, the Keychain-backed AIService and Claude Code's last check. Claude Code is GitHub-only: the App Store build has none.
    @MainActor
    static func aiInput(state: AppState) -> SettingsAI.Input {
        #if APPSTORE
        let githubBuild = false
        #else
        let githubBuild = true
        #endif
        var input = SettingsAI.Input(
            githubBuild: githubBuild, claudeState: .notInstalled, claudeVersion: nil, claudeSignIn: "", claudeEnabled: false,
            claudeModel: ClaudeCodeModel.sonnet.rawValue,
            keys: Set(SettingsAI.keyProviders.filter { AIService.shared.key($0) != nil }),
            cloudModel: Dictionary(uniqueKeysWithValues: SettingsAI.keyProviders.map { ($0, AIService.shared.cloudModel($0)) }),
            servers: state.localServers.map { server in
                SettingsAI.Server(id: server.serverID, provider: server.provider, name: server.name,
                                  network: server.placement == .network, models: server.models.map(\.id))
            },
            memory: state.localModelMemory, appleReady: state.appleStatus == .ready)
        #if !APPSTORE
        let status = state.claudeCodeStatus
        input.claudeState = claudeState(status.state)
        input.claudeVersion = status.version
        input.claudeSignIn = ClaudeCodeText.signInWords(status.authMethod)
        input.claudeEnabled = state.claudeCodeEnabled
        input.claudeModel = state.claudeCodeModel.rawValue
        input.codexState = codexState(state.codexStatus.state)
        #endif
        return input
    }

    /// The chooser's pop-up for one feature: Auto, then Cloud (providers with a key), the Claude plan's models when it is ready, Local (by server), Apple on-device,
    /// and the choice that is not running now, so the pop-up keeps it.
    @MainActor
    private static func choiceSections(state: AppState, feature: AIFeature) -> [AIChoiceSection] {
        var out: [AIChoiceSection] = []
        let cloud = AICatalog.cloudOrder.filter { AIService.shared.key($0) != nil }
        if !cloud.isEmpty {
            let items: [(label: String, value: FeatureSetting)] = cloud.map { p in
                let model = AIService.shared.cloudModel(p)
                return (label: "\(ChatProvider(p).displayName) · \(model)", value: .explicit(ModelRef(provider: p, model: model)))
            }
            out.append(AIChoiceSection(id: "cloud", title: "Cloud", items: items))
        }
        #if !APPSTORE
        if state.claudeCodeEnabled, state.claudeCodeStatus.isReady {
            let items: [(label: String, value: FeatureSetting)] = ClaudeCodeModel.allCases.map { m in
                (label: "Claude plan · \(m.label)", value: .explicit(ModelRef(provider: .claudeCode, model: m.rawValue)))
            }
            out.append(AIChoiceSection(id: "plan", title: "Claude plan", items: items))
        }
        if state.codexStatus.isReady {
            let items: [(label: String, value: FeatureSetting)] = [(label: "OpenAI plan", value: .explicit(ModelRef(provider: .codexPlan, model: "")))]
            out.append(AIChoiceSection(id: "openaiPlan", title: "OpenAI plan", items: items))
        }
        #endif
        let servers = state.localServers.filter(\.isReady)
        if !servers.isEmpty {
            let items: [(label: String, value: FeatureSetting)] = servers.flatMap { s in
                s.models.map { m -> (label: String, value: FeatureSetting) in
                    (label: "\(s.name) · \(m.id)", value: .explicit(ModelRef(provider: s.provider, model: m.id, serverID: s.serverID)))
                }
            }
            out.append(AIChoiceSection(id: "local", title: "Local", items: items))
        }
        if state.appleStatus == .ready {
            let items: [(label: String, value: FeatureSetting)] = [(label: "Apple on-device", value: .explicit(ModelRef(provider: .apple, model: "system")))]
            out.append(AIChoiceSection(id: "apple", title: "Apple on-device", items: items))
        }
        if case .explicit(let ref) = state.choice(for: feature), !isListed(ref, state: state) {
            let label = ref.provider == .codexPlan ? "OpenAI plan (not running)" : "\(ChatProvider(ref.provider).displayName) · \(ref.model) (not running)"
            let items: [(label: String, value: FeatureSetting)] = [(label: label, value: .explicit(ref))]
            out.append(AIChoiceSection(id: "missing", title: nil, items: items))
        }
        return out
    }

    /// Whether a choice is in the pop-up now (a server that is off is not, and the pop-up keeps it as "not running").
    @MainActor
    private static func isListed(_ ref: ModelRef, state: AppState) -> Bool {
        if ref.provider == .codexPlan {
            #if !APPSTORE
            return state.codexStatus.isReady
            #else
            return false
            #endif
        }
        if ref.provider == .claudeCode {
            #if !APPSTORE
            return state.claudeCodeEnabled && state.claudeCodeStatus.isReady
            #else
            return false
            #endif
        }
        if ref.provider.isCloud { return AIService.shared.key(ref.provider) != nil && AIService.shared.cloudModel(ref.provider) == ref.model }
        if ref.provider == .apple { return state.appleStatus == .ready }
        return state.localServers.contains { $0.isReady && $0.serverID == (ref.serverID ?? ref.provider.rawValue)
            && $0.models.contains { $0.id == ref.model } }
    }

    /// The network note of a server on the network: "unencrypted" when its address is plain http.
    private static func networkNote(_ server: DiscoveredServer) -> String? {
        guard server.placement == .network else { return nil }
        return server.baseURL.lowercased().hasPrefix("http://") ? "network · unencrypted on your network" : "network"
    }

    /// The get or update link of a local server (the words and the address are SettingsAI's); nil when it is running or the server is a cloud one.
    private static func getLink(_ server: DiscoveredServer) -> (label: String, url: URL)? {
        guard let text = SettingsAI.getLink(server.provider), let url = URL(string: text) else { return nil }
        switch server.status {
        case .outdated: return (label: "Update", url: url)
        case .notInstalled: return (label: "Get \(server.name)", url: url)
        case .running, .off: return nil
        }
    }

    #if !APPSTORE
    /// Claude Code's state, case for case, as the pure rules name it.
    private static func claudeState(_ s: ClaudeCodeStatus.State) -> SettingsAI.ClaudeState {
        switch s {
        case .notInstalled: return .notInstalled
        case .tooOld: return .tooOld
        case .signedOut: return .signedOut
        case .signedIn: return .signedIn
        case .unknown: return .unknown
        }
    }

    /// Codex's state, case for case, as the pure rules name it (the OpenAI plan's row).
    private static func codexState(_ s: CodexStatus.State) -> SettingsAI.ClaudeState {
        switch s {
        case .notInstalled: return .notInstalled
        case .tooOld: return .tooOld
        case .signedOut: return .signedOut
        case .signedIn: return .signedIn
        case .unknown: return .unknown
        }
    }

    /// The Claude plan's line, word for word from the view it replaces (ConnectClaudePlanView.line).
    private static func claudeLine(_ status: ClaudeCodeStatus) -> String {
        let version = status.version.map { " \($0)" } ?? ""
        switch status.state {
        case .notInstalled: return "Claude Code isn't installed on this Mac."
        case .tooOld: return "Claude Code\(version) is too old for this."
        case .signedOut: return "Claude Code\(version) is signed out. Signing in opens Terminal, and finishes in your browser."
        case .unknown: return "Couldn't ask Claude Code. Is it installed properly?"
        case .signedIn: return "✓ Claude Code\(version), signed in with \(ClaudeCodeText.signInWords(status.authMethod))."
        }
    }
    #endif
}
