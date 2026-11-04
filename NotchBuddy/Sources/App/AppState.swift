import Foundation
import SwiftUI
import Combine
import QuartzCore


@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // Island state
    @Published var mode: IslandMode = .hidden {
        // The greeting's tail (below) only lives in the compact island: any other mode ends it, so a stale flag never brings the canvas back.
        didSet { if mode != .compact { greetingTail = false } }
    }
    @Published var view: IslandView = .overview
    /// True from the moment the island folds at the end of the launch greeting until the greeting's last beat (the session cats' glide into
    /// the grid) is over: the greeting canvas stays up in the compact island until then, and the real cat and mini grid wait for it.
    @Published var greetingTail = false
    /// True while the compact island has stepped aside for the pointer on either wing: the island shrinks into the notch, its cats, grid and badges fade out, and the panel passes the
    /// mouse on to the menu bar under both wings. Set only by `IslandWindowController.pollFrame`, from `IslandWing.Yield`.
    @Published var wingYielded = false

    // Tasks
    @Published var tasks: [AgentTask] = []
    @Published var focusId: String? = nil

    // Bot state override
    @Published var stateOverride: BotState? = nil
    /// True while the idle cat is asleep: ten minutes with no agent event (`CatSleepClock`). The cat then shows `.sleeping` instead of `.idle`.
    @Published var catAsleep = false
    /// Where the desktop cat's trip is (`DesktopCatController`). While the cat is out (`DesktopPhase.notchEmpty`) the big cat's spot in the notch, its kittens and its hit area are empty:
    /// there are never two copies of one cat.
    @Published var desktopPhase = DesktopPhase.home
    /// Each agent pill's subagents, shown as kittens beside its cat (`CatKittens`, changed only by `kittenEvent`). Never stored: a restart starts with none.
    @Published var kittens: [String: [CatKittens.Kitten]] = [:]
    /// Settings → Cat → Display and the Main cat: when either changes, the island's views read the cast again (`storeWatch`).
    private var storeWatch: AnyCancellable?

    // Real notch dimensions (set by IslandWindowController on launch)
    var notchWidth:  CGFloat = IslandConst.notchWidth
    var notchHeight: CGFloat = IslandConst.notchHeight
    var hasNotch = true

    // Last app active before NotchBuddy (for window context capture)
    var lastExternalApp: NSRunningApplication? = nil

    // Bot drag-attach state (hides original bot while ghost follows cursor)
    @Published var isDraggingBot: Bool = false

    // Mouse tracking
    var mousePosition: CGPoint = .zero
    var lastMouseMove: Date = .now
    var lastActivity: Date = .now
    /// When each pill last had a hook event, in ms on the `CACurrentMediaTime()` clock (`touchPill`). Two cats mode picks the busiest other agent with it, and Settings → Cat lists the agents by it.
    /// Not published by itself: the events that set it change the tasks too, and the views redraw for those; `touchPill` announces a change on its own only when an event reorders the agents' list.
    var pillLastEvent: [String: Double] = [:]
    func touchPill(_ id: String, at ms: Double = CACurrentMediaTime() * 1000) {
        if CatAgentList.touchReorders(pillLastEvent, id: id) { objectWillChange.send() }
        pillLastEvent[id] = ms
        agentActivity.send()   // every hook event and alert: the tuck-away count starts again (IslandStateMachine.agentActivity)
    }
    /// Each hook event and alert (`touchPill`), and nothing else: the island's tuck-away count reads it. Not published.
    let agentActivity = PassthroughSubject<Void, Never>()
    /// The app a Claude Code session runs in when it is not VS Code (the relay's `__CFBundleIdentifier`, else the terminal `TERM_PROGRAM` names), by pill; the Claude Code
    /// pill's tap brings it forward. Not published: the events that set it change the tasks too.
    var hostBundleIds: [String: String] = [:]
    /// Where each Claude Code session runs, by session ID (`HookOrigin.TapHost`): an app, or `.noApp` when none is known (VS Code, or a terminal we do not map). A session with no entry is one not seen yet. Not published.
    var sessionHosts: [String: HookOrigin.TapHost] = [:]
    /// The session that sent each pill its last event, by pill: the pill's current session for its tap. Not published.
    var pillSessions: [String: String] = [:]
    func noteHost(_ pillId: String, session sessionId: String, _ bundleId: String?) {
        if let bundleId { hostBundleIds[pillId] = bundleId; sessionHosts[sessionId] = .app(bundleId) } else { hostBundleIds.removeValue(forKey: pillId); sessionHosts[sessionId] = .noApp }
        pillSessions[pillId] = sessionId
    }
    func forgetSession(_ sessionId: String) { sessionHosts.removeValue(forKey: sessionId) }
    /// Whether the pill's current session runs in the Claude app (the finished card's "Open Claude" and the pill's tap read it).
    func pillRunsInClaudeApp(_ pillId: String) -> Bool {
        guard let session = pillSessions[pillId] else { return false }
        return HookOrigin.isClaudeAppHost(sessionHosts[session])
    }
    var isPresent: Bool = true

    // Pinned (alerts that stay open, never auto-close)
    var isPinned: Bool = false

    // Keyboard navigation: the selected row of the list on the card on screen (nil = none), and how
    // many rows that list has (0 = the card has no list).
    @Published var cardSelection: Int? = nil
    @Published var cardItemCount: Int = 0

    // Upload progress (0-1) — set to 1.0 only at completion; animation is time-based
    @Published var uploadProgress: Double = 0

    // Upload animation timing (non-published — TimelineViews read these directly)
    var uploadStartTime: Date?
    var uploadDuration: Double = 2.4

    // File drag-over state (the drop zone's hover glow)
    @Published var fileDragOver: Bool = false
    /// The agent whose own cat a dragged file is over (sub-project F1): the grid cat or cat 2 draws a thin ring while it is. nil the rest of the time.
    @Published var sidekickDropPill: String? = nil
    /// The one line a drop on an agent's cat shows in the island's `.sidekick` row (owner's answer 2, 2026-10-14): nil the rest of the time. `SidekickDropApp` sets and clears it.
    @Published var sidekickDropLine: String? = nil
    /// The half of the open island the dragged files are over (sub-project G1): nil when no drag is over the notch. The upload canvas is the Ask half; ShelfDropLayer draws the Shelf half.
    @Published var dropHalf: DropHalf? = nil
    /// Files are being dragged out of the shelf, or the share picker is open: the island stays open and the panel keeps taking the mouse (sub-project G1).
    @Published var shelfDragging: Bool = false
    /// When the share picker opened (`ProcessInfo.systemUptime`), nil while it is closed. A clock reading, not a flag, so that a callback that never comes cannot hold the island open for ever (`ShelfHold`).
    @Published var sharePickerSince: Double? = nil
    var shelfHoldsIsland: Bool { ShelfHold.isHeld(dragging: shelfDragging, pickerSince: sharePickerSince, now: ProcessInfo.processInfo.systemUptime) }
    /// A machine this Mac is paired with offered a file and its Accept card is waiting for a click (sub-project G2). It is an alert like an approval: it opens the island even when hidden, holds it
    /// open, and the desktop cat flies to the notch for it (`transferOffer` in `desktopAlert`). `LinkService` sets and clears it.
    @Published var linkOfferPending: Bool = false
    /// A pairing card, an Accept card or a file coming in is on the `.link` view: the island stays open until it is answered or over (`LinkService`).
    @Published var linkHoldsIsland: Bool = false

    // Sound enabled — persisted
    @Published var soundEnabled: Bool = true {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled") }
    }

    // Claude model used by the chat and the search — persisted (Anthropic's remembered model)
    static let defaultClaudeModel = AICatalog.info(.anthropic).defaultModel!
    @Published var claudeModel: String = AppState.defaultClaudeModel {
        didSet { UserDefaults.standard.set(claudeModel, forKey: "claudeModel") }
    }

    // Remembered cloud models (Google, OpenAI) — persisted
    @Published var googleChatModel: String = ChatProvider.google.defaultModel {
        didSet { UserDefaults.standard.set(googleChatModel, forKey: "googleChatModel") }
    }
    @Published var openAIChatModel: String = ChatProvider.openai.defaultModel {
        didSet { UserDefaults.standard.set(openAIChatModel, forKey: "openAIChatModel") }
    }

    // MARK: AI routing (E1) — persisted

    /// Per feature ("chat", "files"): Auto or one chosen model.
    @Published var aiChoices: [String: FeatureSetting] = [:] {
        didSet { Self.saveJSON(aiChoices, "aiChoices") }
    }
    /// Which cloud Auto tries first when both Claude and OpenAI keys exist.
    @Published var preferredCloud: AIProviderID = .anthropic {
        didSet { UserDefaults.standard.set(preferredCloud.rawValue, forKey: "aiPreferredCloud") }
    }
    @Published var lastUsedLocal: ModelRef? = nil {
        didSet { Self.saveJSON(lastUsedLocal, "aiLastUsedLocal") }
    }
    /// Servers added in Settings → AI (keys in the Keychain).
    @Published var customServers: [CustomServer] = [] {
        didSet { Self.saveJSON(customServers, "aiCustomServers") }
    }
    #if !APPSTORE
    /// The user connected "Use my Claude plan": Auto may use it while the last check finds Claude Code signed in.
    @Published var claudeCodeEnabled: Bool = false {
        didSet { UserDefaults.standard.set(claudeCodeEnabled, forKey: "aiClaudeCodeEnabled") }
    }
    /// Claude Code's model alias for the chat (sonnet, opus, haiku).
    @Published var claudeCodeModel: ClaudeCodeModel = .sonnet {
        didSet { UserDefaults.standard.set(claudeCodeModel.rawValue, forKey: "aiClaudeCodeModel") }
    }
    #endif
    /// Last model used on each local server, by server ID.
    @Published var localModelMemory: [String: String] = [:] {
        didSet { Self.saveJSON(localModelMemory, "aiLocalModels") }
    }
    #if !APPSTORE
    /// What the last check found of Codex (the OpenAI plan): Settings opening, the model picker, a turn that names the plan. Memory only; never on a timer.
    @Published var codexStatus: CodexStatus = .notInstalled
    #endif

    // MARK: AI routing (E1) — live

    @Published var localServers: [DiscoveredServer] = []
    @Published var appleStatus: AppleOnDevice.Status = .hidden
    @Published var isOnline: Bool = true
    #if !APPSTORE
    /// What the last check found of Claude Code (Settings opening, a chat's first turn): never on a timer.
    @Published var claudeCodeStatus: ClaudeCodeStatus = .notInstalled
    /// What the last Claude Code run said about itself (who pays, which model).
    @Published var claudeRunReport: EngineReport? = nil
    /// The level of the current chat. Every new chat starts at Chat only.
    @Published var claudeLevel: ClaudeCodeLevel = .chatOnly
    /// A quick Explain's chat is held at no tools until the user picks a level. Memory only: never stored, never on a timer.
    @Published var claudeQuickHold: Bool = false
    /// The step Claude Code is waiting to take in the current chat (Agent level).
    @Published var chatApproval: ChatApproval? = nil
    #endif
    /// "Waking up qwen3.5…" or the busy countdown, shown where the typing dots are.
    @Published var chatNotice: ChatNotice? = nil
    /// A reply is streaming: the send button becomes Stop.
    @Published var chatStreaming: Bool = false
    /// Drop card line: who will read the file, or why it can't be read.
    @Published var dropReaderLine: String? = nil
    @Published var dropRejected: Bool = false
    /// Optional button for the current note (only shown while `noteMessage` is the one it was made for).
    @Published var noteAction: NoteAction? = nil
    /// Set to open the model picker from an error's "Choose model".
    @Published var openModelPicker: Bool = false

    func choice(for feature: AIFeature) -> FeatureSetting { aiChoices[feature.rawValue] ?? .auto }

    func setChoice(_ setting: FeatureSetting, for feature: AIFeature) {
        aiChoices[feature.rawValue] = setting
        if case .explicit(let ref) = setting { remember(ref) }
    }

    /// Remembers the model per provider (cloud) or per server (local).
    func remember(_ ref: ModelRef) {
        switch ref.provider {
        case .anthropic: claudeModel = ref.model
        case .openai: openAIChatModel = ref.model
        case .google: googleChatModel = ref.model
        case .apple: break
        case .claudeCode:
            #if !APPSTORE
            claudeCodeModel = ClaudeCodeModel(rawValue: ref.model) ?? .sonnet
            #endif
        case .codexPlan: break
        default: localModelMemory[ref.serverID ?? ref.provider.rawValue] = ref.model
        }
    }

    private static func saveJSON<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }

    private static func loadJSON<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    /// First launch with E1 only (see `AISettingsMigration`).
    private func migrateChatSettings(_ ud: UserDefaults) {
        guard ud.object(forKey: "aiChoices") == nil else { return }
        let keys = ["chatProvider", "ollamaServerURL", "lmstudioServerURL", "ollamaChatModel",
                    "lmstudioChatModel", "openAIChatModel", "googleChatModel"]
        var old: [String: String] = [:]
        for key in keys { old[key] = ud.string(forKey: key) }
        let r = AISettingsMigration.migrate(old)
        customServers = r.customServers
        localModelMemory = r.localModels
        aiChoices = r.choices   // always written, so this runs once
    }

    // The always-on workspace pill (default: Claude Code). Persisted.
    @Published var mainPillId: String = PillCatalog.defaultMainPillId {
        didSet { UserDefaults.standard.set(mainPillId, forKey: "mainPill") }
    }

    // Dynamically fetched cloud model lists for the in-chat picker
    @Published var fetchedProviderModels: [AIProviderID: [ModelInfo]] = [:]
    @Published var providerModelFetchError: [AIProviderID: String] = [:]
    @Published var loadingProviderModels: Set<AIProviderID> = []

    /// Fetches a cloud provider's models if not already loaded or loading.
    func fetchModelsIfNeeded(for provider: AIProviderID) {
        guard provider.isCloud, provider != .claudeCode, provider != .codexPlan, !loadingProviderModels.contains(provider),
              fetchedProviderModels[provider] == nil else { return }
        guard let key = AIService.shared.key(provider) else {
            providerModelFetchError[provider] = "No API key — add it in Settings."
            return
        }
        loadingProviderModels.insert(provider)
        providerModelFetchError.removeValue(forKey: provider)
        Task {
            let result = await AIService.shared.listCloudModels(provider, key: key)
            loadingProviderModels.remove(provider)
            if !result.models.isEmpty {
                fetchedProviderModels[provider] = result.models
            } else {
                let failure = AIMessages.listFailure(result.failure, provider: provider, online: isOnline)
                providerModelFetchError[provider] = failure.rejected ? "Failed to load models. Check your API key." : failure.text
            }
        }
    }

    // Sound volume (0–0.2) — persisted, synced to SoundEngine
    @Published var soundVolume: Double = 0.12 {
        didSet {
            UserDefaults.standard.set(soundVolume, forKey: "soundVolume")
            SoundEngine.shared.volume = Float(soundVolume)
        }
    }

    // Context for prompt (window attach / file)
    @Published var promptContext: PromptContext? = nil

    // Dropped file (set during upload flow)
    @Published var droppedFile: DroppedFile? = nil

    // Short note message (shown in NoteView)
    @Published var noteMessage: String? = nil

    // Hovering the island opens it (it folds 0.6 s after the pointer leaves) — persisted, off by default
    @Published var openOnHover: Bool = false {
        didSet { UserDefaults.standard.set(openOnHover, forKey: "openOnHover") }
    }
    // Settings → General → Behavior → Tuck the island away: when the compact island hides by itself (IslandTuckAway) — persisted, "never" by default
    @Published var tuckAway: IslandTuckAway.Choice = .never {
        didSet { UserDefaults.standard.set(tuckAway.rawValue, forKey: IslandTuckAway.defaultsKey) }
    }
    // The hover glow along the island's outline (IslandGlow) — persisted, on by default
    @Published var hoverGlow: Bool = true {
        didSet { UserDefaults.standard.set(hoverGlow, forKey: IslandGlow.defaultsKey) }
    }
    // Settings → General → Island → Step back when I'm already in the app (FocusAware) — persisted, on by default
    @Published var focusAware: Bool = true {
        didSet { UserDefaults.standard.set(focusAware, forKey: FocusAware.defaultsKey) }
    }
    // The sessions that stepped back to their own app, in memory only; ended by FocusAware.Marks.end and read for age by the views
    @Published var focusMarks = FocusAware.Marks()
    /// The pointer is over the island (set by the poll only when it changes): the glow's trigger. Not persisted.
    @Published var islandHovered: Bool = false
    @Published var autoCloseInterval: TimeInterval = 15 {
        didSet { UserDefaults.standard.set(autoCloseInterval, forKey: "autoCloseInterval") }
    }

    // Greeting threshold — how long hidden before greeting on reappear (default 2 min)
    var greetThresholdSeconds: TimeInterval = 120 {
        didSet { UserDefaults.standard.set(greetThresholdSeconds, forKey: "greetThreshold") }
    }

    // Hotkey to open or close the island (⌘⇧N by default). It is stored with the other shortcuts, in
    // ShortcutLogic (same UserDefaults keys as before), so General and Settings → General → Shortcuts show one value.
    var hotkeyEnabled: Bool {
        get { ShortcutLogic.isEnabled(.toggleIsland) }
        set { objectWillChange.send(); ShortcutLogic.setEnabled(newValue, for: .toggleIsland) }
    }
    var hotkeyFlags: UInt {
        get { ShortcutLogic.hotKey(for: .toggleIsland).nsFlags }
        set {
            var spec = ShortcutLogic.hotKey(for: .toggleIsland)
            spec.nsFlags = newValue
            ShortcutLogic.save(spec, for: .toggleIsland)
        }
    }
    var hotkeyCode: UInt16 {
        get { ShortcutLogic.hotKey(for: .toggleIsland).keyCode }
        set {
            var spec = ShortcutLogic.hotKey(for: .toggleIsland)
            spec.keyCode = newValue
            ShortcutLogic.save(spec, for: .toggleIsland)
        }
    }

    // Vercel project filter — empty = watch all projects
    @Published var vercelProjectFilter: Set<String> = [] {
        didSet {
            if let data = try? JSONEncoder().encode(Array(vercelProjectFilter)) {
                UserDefaults.standard.set(data, forKey: "vercelProjectFilter")
            }
        }
    }

    // n8n workflow filter — empty = watch all workflows
    @Published var n8nWorkflowFilter: Set<String> = [] {
        didSet {
            if let data = try? JSONEncoder().encode(Array(n8nWorkflowFilter)) {
                UserDefaults.standard.set(data, forKey: "n8nWorkflowFilter")
            }
        }
    }

    // Active integration pills (main workspace pill excluded). Max 4.
    @Published var activeIntegrations: Set<String> = ["integration_resend", "integration_n8n", "integration_vercel", "integration_github"] {
        didSet {
            if let data = try? JSONEncoder().encode(Array(activeIntegrations)) {
                UserDefaults.standard.set(data, forKey: "activeIntegrations")
            }
            // Clear stale GitHub data when the integration is disabled
            if !activeIntegrations.contains("integration_github") && oldValue.contains("integration_github") {
                githubPulse = nil
                githubActivity = nil
            }
        }
    }

    // Pending API result
    @Published var searchResult: SearchResult? = nil

    // Vercel deployments (populated by VercelPoller)
    @Published var vercelDeployments: [VercelDeployment] = []

    // Resend emails (populated by ResendPoller)
    @Published var resendEmails: [ResendEmail] = []
    @Published var resendTotal: Int? = nil

    // GitHub stats + pulse + activity (populated by GithubPoller)
    @Published var githubStats: GitHubStats? = nil
    @Published var githubPulse: GitHubPulse? = nil
    @Published var githubActivity: GitHubActivity? = nil

    // Stripe (populated by StripePoller)
    @Published var stripePayments: [StripePayment] = []
    @Published var stripeBalance: Int = 0           // raw balance in cents
    @Published var stripeDisplayBalance: Int = 0    // animated balance target
    @Published var stripeCurrency: String = "eur"
    @Published var stripeLoaded: Bool = false       // true after first successful poll
    @Published var stripeError: String? = nil      // last API error (nil = ok)

    // Cal.com (populated by CalcomPoller)
    @Published var calcomBookings: [CalcomBooking] = []
    @Published var calcomLoaded: Bool = false
    @Published var calcomError: String? = nil

    // Notion (populated by NotionPoller)
    @Published var notionPages: [NotionPage] = []
    @Published var notionLoaded: Bool = false
    @Published var notionError: String? = nil

    // Chat conversation history
    @Published var chatHistory: [ChatMessage] = []
    /// The chat's pane: the conversation, or the list of stored conversations (CompanionViews).
    @Published var chatPane: ChatPane = .chat
    /// The chat lives in its own window (CompanionWindowController): the island's chat view shows a note instead of a second live chat.
    @Published var chatPoppedOut = false
    /// The card above the chat's field for a Fix or Rewrite (CompanionQuickRun, QuickResultCard): the running state, then the cleaned text. Memory only.
    @Published var quickResult: QuickResult? = nil

    // Pending approval request from Claude Code hook
    @Published var pendingApproval: ApprovalInfo? = nil

    // Pending AskUserQuestion from Claude Code hook
    @Published var pendingQuestion: AskQuestion? = nil {
        didSet { QuestionLayout.height = pendingQuestion?.estimatedIslandHeight }
    }

    // Per-pill flat list of FileDiffs, in order of reception.
    // Not @Published — steps[] changes already trigger redraws.
    var sessionDiffs: [String: [FileDiff]] = [:]
    private var sessionDiffTimers: [String: DispatchWorkItem] = [:]
    // Monotonically increasing — never reset, not even in clearSessionDiffs.
    private var nextDiffId: Int = 0

    @discardableResult
    func appendSessionDiff(_ diff: FileDiff, for pillId: String) -> Int {
        var d = diff
        d.id = nextDiffId
        nextDiffId += 1
        if sessionDiffs[pillId] == nil { sessionDiffs[pillId] = [] }
        sessionDiffs[pillId]!.append(d)
        // Keep at most 50 diffs per pill; drop oldest first
        while sessionDiffs[pillId]!.count > 50 {
            sessionDiffs[pillId]!.removeFirst()
        }
        resetSessionDiffTimer(for: pillId)
        return d.id
    }

    func clearSessionDiffs(for pillId: String) {
        sessionDiffTimers[pillId]?.cancel()
        sessionDiffTimers.removeValue(forKey: pillId)
        sessionDiffs.removeValue(forKey: pillId)
        // nextDiffId intentionally NOT reset — ids remain unique across sessions
    }

    private func resetSessionDiffTimer(for pillId: String) {
        sessionDiffTimers[pillId]?.cancel()
        // The closure is MainActor-isolated (AppState is @MainActor): it must run on the main queue.
        // Scheduled on a global queue, Swift 6's isolation check traps an hour later and the app quits.
        let work = DispatchWorkItem { [weak self] in
            self?.clearSessionDiffs(for: pillId)
        }
        sessionDiffTimers[pillId] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3600, execute: work)
    }

    #if !APPSTORE
    @Published var musicPlaying: Bool = false
    @Published var musicAutomationDenied: Bool = false
    #endif

    // Claude plan gauge (from statusline hook)
    @Published var claudePlanUsage: PlanUsage? = nil {
        didSet {
            if let u = claudePlanUsage,
               let data = try? JSONEncoder().encode(u) {
                UserDefaults.standard.set(data, forKey: "claudePlanUsage")
            }
        }
    }

    // Plan gauge: show pill in notch header — persisted
    #if !APPSTORE
    @Published var showPlanInNotch: Bool = false {
        didSet { UserDefaults.standard.set(showPlanInNotch, forKey: "showPlanInNotch") }
    }
    // Cached relay-installed state — updated at launch, after install/uninstall, on Settings open
    @Published var planRelayInstalled: Bool = false
    // Transient — reset when island closes or view changes
    @Published var showingPlanDetail: Bool = false

    func refreshPlanRelayState() {
        planRelayInstalled = HookServer.statusLineInstalled()
    }
    #endif

    // MARK: - Init (loads persisted settings)

    private init() {
        let ud = UserDefaults.standard

        if let v = ud.object(forKey: "soundEnabled") as? Bool   { soundEnabled = v }
        if let v = ud.object(forKey: "soundVolume")  as? Double { soundVolume  = v }
        if let v = ud.string(forKey: "claudeModel"),
           !v.trimmingCharacters(in: .whitespaces).isEmpty { claudeModel = v }
        if let v = ud.string(forKey: "googleChatModel"), !v.isEmpty { googleChatModel = v }
        if let v = ud.string(forKey: "openAIChatModel"), !v.isEmpty { openAIChatModel = v }
        if let v = Self.loadJSON([String: FeatureSetting].self, "aiChoices") { aiChoices = v }
        if let v = ud.string(forKey: "aiPreferredCloud"), let p = AIProviderID(rawValue: v) { preferredCloud = p }
        if let v = Self.loadJSON(ModelRef.self, "aiLastUsedLocal") { lastUsedLocal = v }
        if let v = Self.loadJSON([CustomServer].self, "aiCustomServers") { customServers = v }
        if let v = Self.loadJSON([String: String].self, "aiLocalModels") { localModelMemory = v }
        #if !APPSTORE
        if let v = ud.object(forKey: "aiClaudeCodeEnabled") as? Bool { claudeCodeEnabled = v }
        if let v = ud.string(forKey: "aiClaudeCodeModel"), let m = ClaudeCodeModel(rawValue: v) { claudeCodeModel = m }
        #endif
        migrateChatSettings(ud)
        if let v = ud.object(forKey: "openOnHover") as? Bool { openOnHover = v }
        tuckAway = IslandTuckAway.choice(stored: ud.string(forKey: IslandTuckAway.defaultsKey))
        if let v = ud.object(forKey: IslandGlow.defaultsKey) as? Bool { hoverGlow = v }
        focusAware = FocusAware.enabled(stored: ud.object(forKey: FocusAware.defaultsKey))
        // Migrate old 60s default → 15s
        if let v = ud.object(forKey: "autoCloseInterval") as? Double {
            autoCloseInterval = (v == 60) ? 15 : v
        }
        if let v = ud.object(forKey: "greetThreshold")    as? Double { greetThresholdSeconds = v }
        if let d = ud.data(forKey: "vercelProjectFilter"),
           let a = try? JSONDecoder().decode([String].self, from: d) { vercelProjectFilter = Set(a) }
        if let d = ud.data(forKey: "n8nWorkflowFilter"),
           let a = try? JSONDecoder().decode([String].self, from: d) { n8nWorkflowFilter = Set(a) }
        if let d = ud.data(forKey: "activeIntegrations"),
           let a = try? JSONDecoder().decode([String].self, from: d) { activeIntegrations = Set(a) }
        if let v = ud.string(forKey: "mainPill"), !v.isEmpty,
           PillCatalog.available.contains(where: { $0.id == v && $0.category == .workspace && !$0.comingSoon }) {
            mainPillId = v
        }
        if let d = ud.data(forKey: "claudePlanUsage"),
           let u = try? JSONDecoder().decode(PlanUsage.self, from: d) { claudePlanUsage = u }
        #if !APPSTORE
        if let v = ud.object(forKey: "showPlanInNotch") as? Bool { showPlanInNotch = v }
        planRelayInstalled = HookServer.statusLineInstalled()
        #endif

        // Sync SoundEngine volume on launch
        SoundEngine.shared.volume = Float(soundVolume)

        // Always load integration pills
        loadIntegrationTasks()

        // The cast (`cast`) is made from the island and from Settings → Cat, so a change of the display mode, the pair, an agent's coat or the Main cat is a change of
        // this object too: the views that read the cast redraw. (Dragging a personality slider is not.)
        let store = CatSettingsStore.shared
        storeWatch = store.$display.map { _ in () }.dropFirst()
            .merge(with: store.$settings.map(\.character).removeDuplicates().dropFirst().map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.objectWillChange.send() }
    }

    // MARK: - Computed

    var focusTask: AgentTask? {
        tasks.first { $0.id == focusId } ?? tasks.first
    }

    /// The state the cat would show if it were awake: the override, else the focused task's.
    var baseState: BotState {
        stateOverride ?? focusTask?.state ?? .idle
    }

    /// The state the cat shows: the base state, and sleeping instead of idle once the sleep timer has fired.
    var effectiveState: BotState {
        baseState.shown(asleep: catAsleep)
    }

    // MARK: - Task management

    func addTask(_ task: AgentTask) {
        guard !tasks.contains(where: { $0.id == task.id }) else { return }
        tasks.append(task)
        giveCoat(to: task.id)
        if focusId == nil { focusId = task.id }
        syncMode()
        syncView()
    }

    func removeTask(id: String) {
        heldPills[id] = nil
        // mainPillId: always reset, never remove (the active workspace tool)
        // activeIntegrations: also reset (user declared it active, keep it as idle)
        let isProtected = id == mainPillId
        let isActiveDecl = PillCatalog.definition(for: id) != nil && activeIntegrations.contains(id)
        if isProtected || isActiveDecl {
            if let idx = tasks.firstIndex(where: { $0.id == id }) {
                let catalogName = PillCatalog.definition(for: id)?.name
                tasks[idx].state      = .idle
                tasks[idx].steps      = []
                tasks[idx].stepIndex  = 0
                tasks[idx].pillBadge  = nil
                if let n = catalogName { tasks[idx].name = n }
            }
            return
        }
        // Undeclared or declared-but-not-active: remove
        kittens[id] = nil
        tasks.removeAll { $0.id == id }
        if focusId == id { focusId = mainPillId }
        syncMode()
        syncView()
    }

    /// A card holds its pill's look: while an approval, or a question, waits on a pill, the states other sessions ask of it are recorded here (with the final line) and shown
    /// when the card closes (`releasePill`). Not published: tasks[] is what the views read.
    private var heldPills: [String: (state: BotState, finalLine: String?)] = [:]
    /// The pill that owns the pending question (set by HookServer when the question arrives).
    var questionPillId: String = ""
    var questionSessionId: String = ""

    func cardWaiting(on id: String) -> Bool { pendingApproval?.pillId == id || (pendingQuestion != nil && questionPillId == id) }

    func updateTask(id: String, state: BotState) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        let waiting = cardWaiting(on: id)
        tasks[idx].state = HookOrigin.shownWhileCard(cardWaiting: waiting, requested: state, current: tasks[idx].state)
        if waiting { heldPills[id] = (state, HookOrigin.heldLine(entryExists: heldPills[id] != nil, held: heldPills[id]?.finalLine, current: tasks[idx].finalLine)) } else { heldPills[id] = nil }
    }

    /// The card's own state (the approval, the question): shown at once, even over another card on the pill; nothing is held for it.
    func showCardState(id: String, state: BotState) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].state = state
        heldPills[id] = nil
    }

    /// The pill's final line (the last message a Stop shows). Held with the state while a card waits on a pill that has a held state.
    func setFinalLine(id: String, _ line: String?) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        if cardWaiting(on: id), heldPills[id] != nil { heldPills[id]?.finalLine = line } else { tasks[idx].finalLine = line }
    }

    /// The card on this pill has closed (the caller has cleared it): the pill shows the latest state held for it, else `fallback` (nil: the state it shows now). Returns what it shows.
    @discardableResult
    func releasePill(id: String, fallback: BotState? = nil) -> BotState? {
        let held = heldPills.removeValue(forKey: id)
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return nil }
        let shown = HookOrigin.shownAfterCard(held: held?.state, fallback: fallback ?? tasks[idx].state)
        tasks[idx].state = shown
        if let held { tasks[idx].finalLine = held.finalLine }
        return shown
    }

    func setFocus(_ id: String) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        focusId = id
        tasks[idx].pillBadge = nil  // clear badge when user brings task to focus
    }

    func setPillBadge(_ badge: PillBadge, for id: String) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].pillBadge = badge
    }

    /// Called on main thread after each GitHub pulse poll. Fires badge + sound based on events.
    func handleGitHubEvents(_ events: [GitHubEvent]) {
        guard !events.isEmpty else { return }
        // Priority: error > question (reviewRequested) > finish (ciPassed)
        var level = 0          // 0 = none, 1 = finish, 2 = question, 3 = error
        var badge: PillBadge?
        var sound: String?
        for event in events {
            switch event {
            case .ciFailed, .mainFailed:
                if level < 3 { level = 3; badge = .error;    sound = "error"    }
            case .reviewRequested:
                if level < 2 { level = 2; badge = .finished; sound = "question" }
            case .ciPassed:
                if level < 1 { level = 1; badge = .finished; sound = "finish"   }
            }
        }
        // Only set badge when the GitHub pill is not currently in focus
        if let b = badge, focusId != "integration_github" { setPillBadge(b, for: "integration_github") }
        if let s = sound { SoundEngine.shared.play(s) }
    }

    func syncMode() {
        // If no tasks and not expanded/peek, go hidden
        if tasks.isEmpty && mode == .compact {
            mode = .hidden
        } else if !tasks.isEmpty && mode == .hidden && isPresent {
            mode = .compact
        }
    }

    func syncView() {
        guard mode == .expanded else { return }
        if view == .empty && !tasks.isEmpty { view = .overview }
        else if view == .overview && tasks.isEmpty { view = .empty }
    }

    /// Load catalog pills into tasks, respecting activeIntegrations. Safe to call multiple times.
    func loadIntegrationTasks() {
        let catalog = PillCatalog.available
        // Sanitize: remove saved IDs not in catalog
        let catalogIds = Set(catalog.map { $0.id })
        activeIntegrations = activeIntegrations.filter { catalogIds.contains($0) }
        // Validate mainPillId: must be a non-comingSoon workspace pill in the catalog
        if !PillCatalog.available.contains(where: { $0.id == mainPillId && $0.category == .workspace && !$0.comingSoon }) {
            mainPillId = PillCatalog.defaultMainPillId
        }
        // mainPillId must never be in activeIntegrations (migration + invariant)
        activeIntegrations.remove(mainPillId)
        for def in catalog {
            // mainPillId always loads; activeIntegrations load
            let shouldLoad = def.id == mainPillId || activeIntegrations.contains(def.id)
            let loaded = tasks.contains(where: { $0.id == def.id })
            if shouldLoad && !loaded {
                let task = AgentTask(id: def.id, name: def.name, color: def.color,
                                     state: .idle, steps: [], source: def.source, isIntegration: true)
                tasks.append(task)
                giveCoat(to: def.id)
            }
            if !shouldLoad && loaded {
                kittens[def.id] = nil
                tasks.removeAll { $0.id == def.id }
            }
        }
        sortTasksByCatalog()
        if focusId == nil { focusId = mainPillId }
        syncMode()
    }

    /// Toggle a catalog pill on/off.
    /// mainPillId: never toggleable (change via the Main picker first).
    /// Max 4 non-main pills active at once.
    func toggleIntegration(_ id: String) {
        guard id != mainPillId else { return }
        guard PillCatalog.available.contains(where: { $0.id == id }) else { return }
        if activeIntegrations.contains(id) {
            activeIntegrations.remove(id)
            kittens[id] = nil
            tasks.removeAll { $0.id == id }
            if focusId == id { focusId = mainPillId }
        } else {
            guard activeIntegrations.count < 4 else { return }
            activeIntegrations.insert(id)
            if let def = PillCatalog.available.first(where: { $0.id == id }),
               !tasks.contains(where: { $0.id == id }) {
                let task = AgentTask(id: def.id, name: def.name, color: def.color,
                                     state: .idle, steps: [], source: def.source, isIntegration: true)
                tasks.append(task)
                giveCoat(to: def.id)
                sortTasksByCatalog()
            }
        }
        syncMode()
    }

    /// Sort tasks so catalog pills are in catalog order, undeclared pills sit right after
    /// integration_claude (matching HookServer insertion behaviour), and the rest follows.
    private func sortTasksByCatalog() {
        let order = PillCatalog.available.enumerated()
            .reduce(into: [String: Int]()) { $0[$1.element.id] = $1.offset }
        let catalogPills    = tasks.filter { order[$0.id] != nil }
        let undeclaredPills = tasks.filter { order[$0.id] == nil }
        let sortedCatalog   = catalogPills.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
        if let claudeIdx = sortedCatalog.firstIndex(where: { $0.id == "integration_claude" }) {
            var result: [AgentTask] = Array(sortedCatalog[...claudeIdx])
            result.append(contentsOf: undeclaredPills)
            if claudeIdx + 1 < sortedCatalog.count {
                result.append(contentsOf: sortedCatalog[(claudeIdx + 1)...])
            }
            tasks = result
        } else {
            tasks = undeclaredPills + sortedCatalog
        }
    }

}

// MARK: - Supporting types

enum PromptContext {
    case window(appName: String, title: String, url: String?)
    case file(name: String, fileURL: URL?)
}

struct DroppedFile {
    var url: URL
    var name: String
}

struct SearchResult {
    var title: String
    var items: [ResultItem]
    var note: String?
}

struct ResultItem {
    var label: String
    var detail: String
    var url: String?
}

// MARK: - Vercel

struct VercelDeployment: Identifiable {
    let id: String
    let projectName: String
    let url: String
    let state: String        // "READY", "ERROR", "CANCELED"
    let createdAt: Date
    let commitMessage: String?
    let branch: String?

    var isSuccess: Bool { state == "READY" }
    var statusLabel: String { isSuccess ? "Ready" : (state == "CANCELED" ? "Canceled" : "Error") }
    var timeAgo: String {
        let diff = Date().timeIntervalSince(createdAt)
        if diff < 60    { return "just now" }
        if diff < 3600  { return "\(Int(diff/60))m" }
        if diff < 86400 { return "\(Int(diff/3600))h" }
        return "\(Int(diff/86400))d"
    }
}

// MARK: - Resend

struct ResendEmail: Identifiable {
    let id: String
    let to: [String]
    let subject: String
    let createdAt: Date
    let lastEvent: String   // "delivered", "bounced", "complained", "opened", etc.

    var recipientShort: String {
        guard let first = to.first else { return "?" }
        return first.components(separatedBy: "@").first ?? first
    }
    var timeAgo: String {
        let diff = Date().timeIntervalSince(createdAt)
        if diff < 60    { return "just now" }
        if diff < 3600  { return "\(Int(diff/60))m" }
        if diff < 86400 { return "\(Int(diff/3600))h" }
        return "\(Int(diff/86400))d"
    }
    var isDelivered: Bool { lastEvent == "delivered" }
}

// MARK: - GitHub

struct GitHubStats {
    let totalRepos: Int
    let totalStars: Int
}

// MARK: - Stripe

struct StripePayment: Identifiable, Equatable {
    let id: String
    let amount: Int         // in cents/smallest unit
    let currency: String
    let description: String?
    let createdAt: Date
    let status: String      // "succeeded", "pending", "failed"

    var amountFormatted: String { String(format: "%.2f", Double(amount) / 100.0) }
    var isSuccess: Bool { status == "succeeded" }
    var timeAgo: String {
        let diff = Date().timeIntervalSince(createdAt)
        if diff < 60    { return "just now" }
        if diff < 3600  { return "\(Int(diff/60))m" }
        if diff < 86400 { return "\(Int(diff/3600))h" }
        return "\(Int(diff/86400))d"
    }
}

// MARK: - Cal.com

struct CalcomBooking: Identifiable, Equatable {
    let id: Int
    let title: String
    let startTime: Date
    let endTime: Date
    let status: String
    let attendeeName: String?
    let attendeeEmail: String?
    let attendeeNotes: String?

    var isActive: Bool { status == "ACCEPTED" || status == "PENDING" }
    var timeLabel: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: startTime)
    }
    var dayKey: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: startTime)
        return "\(c.year!)-\(String(format: "%02d", c.month!))-\(String(format: "%02d", c.day!))"
    }
}

// MARK: - Notion

struct NotionPage: Identifiable {
    let id: String
    let title: String
    let emoji: String?
    let lastEditedAt: Date
    let url: String

    var timeAgo: String {
        let diff = Date().timeIntervalSince(lastEditedAt)
        if diff < 60 { return "now" }
        if diff < 3600 { return "\(Int(diff/60))m" }
        if diff < 86400 { return "\(Int(diff/3600))h" }
        return "\(Int(diff/86400))d"
    }
}

// MARK: - Chat

enum ChatRole { case user, assistant }

/// Which pane the chat shows: the conversation, or the stored conversations (CompanionViews).
enum ChatPane: Equatable { case chat, conversations }

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: ChatRole
    var content: String   // var for streaming updates
    /// Under a reply: "cloud · Claude Sonnet 5.5", "local · qwen3.5:2b".
    var caption: String? = nil
    /// Web search sources (Claude and OpenAI), shown as links.
    var sources: [Citation] = []
    /// One quiet line: fell back to local, file cut short, old messages dropped.
    var notice: String? = nil
    /// The stream was cut: the partial reply is kept with Continue · Retry.
    var interrupted: Bool = false
    /// Steps Claude Code took for this reply (reading a file, running a command), shown as rows above it.
    var steps: [ChatStep] = []
    /// The names of the files a user message carried (never their text): kept with the stored conversation.
    var files: [String] = []
}

/// Shown where the typing dots are: "Waking up qwen3.5…", or the busy countdown with Cancel.
struct ChatNotice: Equatable {
    var text: String
    var cancellable: Bool = false
}

/// The single button under a note, tied to the message it was made for.
struct NoteAction: Equatable {
    let message: String
    let action: AIAction
    /// The message is Markdown with links (the local-model guide).
    var markdown: Bool = false
}
