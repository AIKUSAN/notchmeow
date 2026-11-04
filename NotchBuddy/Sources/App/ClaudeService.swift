import Foundation
import Security

// MARK: - Keychain helpers

enum Keychain {
    static let service = "io.github.aikusan.notchmeow"

    /// True only when the Keychain took the value. Writes in place (KeychainWrite): never deletes first, so a failed write keeps the old value.
    static func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        return KeychainWrite.save(service: service, account: key, data: data)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// True when the Keychain no longer holds the item: deleted now, or absent already (a no-op, not a failure).
    static func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

// MARK: - Keychain cache (reads each key ONCE at launch; all subsequent access via dict)

final class KeychainStore: @unchecked Sendable {
    static let shared = KeychainStore()
    private var cache: [String: String] = [:]
    private let lock = NSLock()

    private static let allKeys = [
        "anthropic-api-key",
        "google-api-key",
        "openai-api-key",
        "resend-api-key", "resend-from",
        "n8n-url", "n8n-api-key",
        "vercel-token",
        "github-token",
        "stripe-api-key",
        "calcom-api-key",
        "notion-api-key",
    ]

    private init() {
        // Called once, on main thread (AppDelegate triggers shared at launch).
        for key in Self.allKeys {
            if let v = Keychain.load(key: key) { cache[key] = v }
        }
    }

    /// Thread-safe read — never touches the Keychain.
    func get(_ key: String) -> String? {
        lock.withLock { cache[key] }
    }

    /// Updates cache + persists to Keychain. True only when the Keychain took the value; on failure the cache keeps what it held.
    @discardableResult
    func set(_ key: String, value: String) -> Bool {
        guard Keychain.save(key: key, value: value) else { return false }
        lock.withLock { cache[key] = value }
        return true
    }

    /// Loads keys only known at runtime (one per added AI server), once, at launch.
    func preload(_ keys: [String]) {
        for key in keys where lock.withLock({ cache[key] == nil }) {
            if let v = Keychain.load(key: key) { lock.withLock { cache[key] = v } }
        }
    }

    /// Removes the key from the Keychain, then from the cache. True only when the Keychain no longer holds it.
    /// Always asks the Keychain, even when the launch read left the cache empty; on failure the cache keeps what it held.
    func remove(_ key: String) -> Bool {
        guard Keychain.delete(key: key) else { return false }
        lock.withLock { cache[key] = nil }
        return true
    }
}

// MARK: - Claude API

@MainActor
final class ClaudeService {
    static let shared = ClaudeService()

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let anthropicVersion = "2023-06-01"

    // MARK: - Model list

    /// Anthropic models, newest first, for the Settings picker. Empty on any error
    /// (callers fall back to a static list).
    static func fetchModels(apiKey: String) async -> [(id: String, label: String)] {
        let models = (try? await AnthropicProvider(apiKey: apiKey).listModels()) ?? []
        return models.map { (id: $0.id, label: $0.label ?? $0.id) }
    }

    /// Chosen in Settings; falls back to the default when the field is left empty.
    private var model: String {
        let m = AppState.shared.claudeModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return m.isEmpty ? AppState.defaultClaudeModel : m
    }

    var apiKey: String? { KeychainStore.shared.get("anthropic-api-key") }

    /// What the model sees of the current chat (provider-independent).
    private var conversation = Conversation()
    /// The stored conversation this chat is saved as: made at its first message, nil until then and after a clear (`storeCurrent`, `open`).
    private(set) var conversationID: String?
    /// A quick Explain's question and the system text it is answered under, for that first turn only (`explain`, `reply`). A new chat forgets it.
    private var quickFirst: QuickFirstTurn?
    /// Bumped on every reset: a reply still on its way is dropped when it lands instead of
    /// being added to the new conversation.
    private var conversationGeneration = 0
    /// The ids of the rows on screen when this chat's stored copy (or every stored conversation) was deleted: a later save never writes them back to disk.
    /// Ids, not positions, so a row removed afterwards (a failed reply's placeholder, Try again, Retry) does not move the others. Reset by `clearConversation`.
    private var forgottenRows: Set<UUID> = []
    /// The message being answered (Stop cancels it).
    private var replyTask: Task<Void, Never>?
    /// Reading a dropped file; the next message waits for it.
    private var preparation: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?

    /// File questions use the `files` route from the message that carries a file onward, everything else `chat`.
    var currentFeature: AIFeature { conversation.feature }

    /// The first image waiting to go out with the next message (the chip "Explain this screenshot" asks about it).
    var pendingImage: PreparedFile? { conversation.pendingFiles.first { $0.kind == .image } }

    #if !APPSTORE
    /// This chat's Claude Code session; replaced when the conversation is cleared.
    private var claudeSession = ClaudeChatSession()
    /// The recap a freshly started session (after a level change moved the folder) is told. `plan` reports the need only
    /// on the call that makes the session, so it is kept here until Claude Code confirms the session: a first turn that
    /// fails before that (and "Try again") must carry it again.
    private var claudeRecap: String?
    /// The session ids whose hook events belong to this chat: `HookServer` routes by them.
    var liveClaudeSessions: Set<String> { quickClaudeSessions.union([claudeSession.sessionID]) }
    /// The sessions of quick actions (`quickReply`), kept after the run ends: their hook events (a late Stop included) are the chat's too, never a session on the island.
    private var quickClaudeSessions: Set<String> = []
    /// The most quick-action session ids kept; the set is emptied when it would pass this (a late hook event of an older run is then a session of the island again).
    static let quickSessionsMax = 64

    /// Claude Code has made the session: the next turn resumes it, from the same folder, and the recap is spent.
    private func claudeSessionStarted(in folder: String) {
        claudeSession.confirmStarted(in: folder)
        claudeRecap = nil
    }
    #endif

    /// Starts over when a new file or window is attached, so the next turn carries it. Clears what
    /// the model gets and the transcript on screen together, like the Windows build does on drop.
    func clearConversation(state: AppState) {
        conversation = Conversation()
        conversationID = nil
        forgottenRows = []
        quickFirst = nil
        conversationGeneration += 1
        replyTask?.cancel()
        countdownTask?.cancel()
        preparation = nil
        state.chatHistory = []
        state.chatNotice = nil
        state.chatStreaming = false
        if state.stateOverride == .thinking { state.stateOverride = nil }
        #if !APPSTORE
        // A new chat: a new Claude Code session at Chat only. The old id is retired with its approvals.
        HookServer.shared.cancelChatApprovals()
        _ = claudeSession.reset()
        claudeRecap = nil
        state.claudeLevel = .chatOnly
        state.claudeQuickHold = false
        #endif
    }

    /// Saves the chat as it stands to its stored conversation, when a reply lands. The sidekick's status rows are never stored, and a file keeps its
    /// name only. A failed save is noted on the reply, in words with no content, and logged by its kind alone.
    func storeCurrent(state: AppState) {
        guard let id = conversationID else { return }
        let rows = state.chatHistory.indices.map { i -> CompanionChatRules.Row in
            let m = state.chatHistory[i]
            let status = m.caption == SidekickChat.caption || Self.isStatusQuestion(state.chatHistory, at: i)
            return CompanionChatRules.Row(id: m.id, role: m.role == .user ? "user" : "assistant", text: m.content, caption: m.caption,
                                          files: m.files, status: status)
        }
        let messages = CompanionChatRules.messages(rows, excluding: forgottenRows)
        // The stored copy of the rows on screen was deleted: only what came after is saved, and nothing newer means nothing is written.
        if !forgottenRows.isEmpty, messages.isEmpty { return }
        let store = Companion.shared.store
        let stored = store.conversation(id: id)
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let record = CompanionConversation(
            id: id, title: stored?.title ?? CompanionRecords.titleOf(CompanionChatRules.titleSource(messages.first { $0.role == "user" }?.text)),
            pinned: stored?.pinned ?? false, createdAt: stored?.createdAt ?? now, updatedAt: now, messages: messages)
        do {
            try store.save(record)
        } catch {
            AILog.record(.companionSaveFailed)
            if let i = state.chatHistory.lastIndex(where: { $0.role == .assistant && !$0.content.isEmpty }) {
                let saveNote = "This conversation could not be saved."
                state.chatHistory[i].notice = [state.chatHistory[i].notice, saveNote].compactMap { $0 }.joined(separator: "\n")
            }
        }
    }

    /// Opens a stored conversation: the chat starts over, then its messages are back on screen and in what the model is sent (a file as a line with
    /// its name only, and its name kept on the row). The next reply is saved to this conversation. A conversation that cannot be read leaves the chat as it is.
    func open(conversationID id: String, state: AppState) {
        // A reply still streaming would finish into the opened chat and take back one of its turns: nothing opens until it ends.
        guard CompanionChatRules.canOpen(streaming: state.chatStreaming, busy: state.stateOverride == .thinking) else { return }
        guard let stored = Companion.shared.store.conversation(id: id) else { return }
        clearConversation(state: state)
        for (m, r) in zip(stored.messages, CompanionChatRules.restored(stored.messages)) {
            if r.role == "user" {
                conversation.addUser(r.modelText)
                state.chatHistory.append(ChatMessage(role: .user, content: m.text, files: r.files))
            } else {
                conversation.addAssistant(r.modelText)
                state.chatHistory.append(ChatMessage(role: .assistant, content: m.text, caption: r.caption))
            }
        }
        conversationID = stored.id
        #if !APPSTORE
        // The recap a session started afresh is told: the restored chat, until `reply` sets it again when a session starts.
        claudeRecap = ClaudeCodeRecap.text(turns: conversation.turns.map { ($0.role, $0.text) })
        #endif
    }

    /// A stored conversation is deleted: when it is this chat's, the chat stops saving to it, and the next reply starts a new one that holds only what comes after
    /// (the rows on screen are not written back).
    func forgetStored(id: String) {
        guard conversationID == id else { return }
        conversationID = nil
        forgottenRows = Set(AppState.shared.chatHistory.map(\.id))
    }

    /// Every stored conversation is deleted: the next reply starts a new one that holds only what comes after, and What the AI saw last is emptied.
    func forgetAllStored() {
        conversationID = nil
        forgottenRows = Set(AppState.shared.chatHistory.map(\.id))
        Companion.shared.clearSent()
    }

    /// Reads a dropped file off the main thread; it joins the next message sent.
    func prepareAttachment(url: URL, state: AppState) {
        let generation = conversationGeneration
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        state.dropReaderLine = nil
        state.dropRejected = false
        preparation = Task {
            let result = await Task.detached(priority: .userInitiated) { AttachmentExtractor.prepare(url: url) }.value
            guard generation == self.conversationGeneration else { return }
            switch result {
            case .success(let file):
                self.conversation.attach(file)
                AILog.record(.attachment(kind: file.kind, bytes: bytes))
                state.dropReaderLine = AIMessages.dropReader(AIService.shared.resolve(.files).primary)
            case .failure(let reason):
                AILog.record(.rejected(reason: reason, bytes: bytes))
                state.dropReaderLine = AIMessages.rejected(reason)
                state.dropRejected = true
            }
        }
    }

    // MARK: - Chat (router → provider, streaming)

    /// Sends a message; Stop cancels it.
    func send(query: String, context: PromptContext?, state: AppState) {
        // "What's Claude doing?" is answered here, from the sidekick's ledger, before a provider is chosen: it never reaches the model's history, so a cloud model never sees it.
        // Its rows do not clear an older partial reply's Continue · Retry: those keep acting on the reply they belong to (retryLast and resendLastMessage look past status rows).
        if SidekickChat.answer(query, state: state) { return }
        // A message typed or sent again is an ordinary turn: only `explain` (which does not come through here) makes a quick first turn.
        quickFirst = nil
        countdownTask?.cancel()
        // A chat's first message names the stored conversation it is saved as.
        if conversationID == nil { conversationID = Companion.shared.store.newConversationId() }
        // Only the newest partial reply keeps Continue · Retry: they act on the last exchange.
        for i in state.chatHistory.indices { state.chatHistory[i].interrupted = false }
        state.chatHistory.append(ChatMessage(role: .user, content: query))
        state.stateOverride = .thinking
        replyTask = Task { await chat(query: query, context: context, state: state) }
    }

    func stop() {
        replyTask?.cancel()
        countdownTask?.cancel()
        #if !APPSTORE
        HookServer.shared.cancelChatApprovals()
        #endif
    }

    func chat(query: String, context: PromptContext?, state: AppState, retries: Int = 0) async {
        // A New chat or an opened conversation while a dropped file is still being read must not receive this message.
        let generation = conversationGeneration
        await preparation?.value
        guard generation == conversationGeneration else { return }
        if conversation.turns.isEmpty, case .window(let app, let title, let url) = context {
            conversation.attachContext("Context — App: \(app), Window: \(title)" + (url.map { ", URL: \($0)" } ?? ""))
        }
        conversation.addUser(query)
        await reply(query: query, context: context, addedUserTurn: true, retries: retries, state: state)
    }

    /// Answers the conversation's last user message. `addedUserTurn`: this call added that message,
    /// so it may take it back on failure; a regenerate (Retry) never removes a user message.
    private func reply(query: String, context: PromptContext?, addedUserTurn: Bool, retries: Int,
                       state: AppState) async {
        let generation = conversationGeneration
        let service = AIService.shared
        #if !APPSTORE
        // Before a chat's first turn: is Claude Code there, and signed in? (Never on a timer.)
        if conversation.turns.count <= 1, state.claudeCodeEnabled || usesClaudeCodeByChoice() {
            await service.refreshClaudeStatus()
            guard generation == conversationGeneration else { return }
        }
        #endif
        #if !APPSTORE
        // The same before the OpenAI plan's turn: a stored chat opened after a relaunch has no check yet (never on a timer).
        if usesCodexByChoice(conversation.feature), conversation.turns.count <= 1 || !state.codexStatus.isReady {
            await service.refreshCodexStatus()
            guard generation == conversationGeneration else { return }
        }
        #endif
        var input = service.routeInput(conversation.feature)
        if ModelRouter.plan(input) == nil {
            // Nothing known yet: a server on this computer may have started since the last scan. Localhost
            // only (0.3 s): a dead added host must not make every send wait 2 s before the empty state.
            _ = await service.freshLocalTarget(for: conversation.feature)
            input = service.routeInput(conversation.feature)
        }
        guard generation == conversationGeneration else { return }
        guard let plan = ModelRouter.plan(input) else {
            if addedUserTurn { conversation.removeLastUser() }
            state.stateOverride = nil
            state.chatNotice = nil
            return  // PromptView shows the empty state
        }
        let primary = service.primaryTarget(plan)
        // The companion's prompt is read for every turn, so "Right now" and the date stay current.
        let parts = Companion.shared.turnParts()
        // A quick Explain's first turn is answered under its own system text; every other turn under the companion's.
        let firstSystem = quickFirst?.system(forQuery: query, turnCount: conversation.turns.count)
        var factory = service.factory()
        #if !APPSTORE
        var claudeFolder = ""
        if primary.provider == .claudeCode {
            // A quick Explain's first turn answers text taken from another app, so it runs with no tools, because its text is untrusted. A held chat stays
            // at no tools until the user picks a level (ClaudeQuickHold); a level that moves the folder starts a fresh session with a recap.
            claudeSession.level = ClaudeQuickHold.level(held: firstSystem != nil || state.claudeQuickHold, chosen: state.claudeLevel)
            claudeSession.model = ClaudeCodeModel(rawValue: primary.model) ?? state.claudeCodeModel
            let chatFolder = ClaudeCodeFolders.chatFolder()
            let next = claudeSession.plan(chatFolder: chatFolder)
            if next.retired != nil { HookServer.shared.cancelChatApprovals() }
            // A session started afresh in the middle of a chat is told what was said before (the new message is last).
            // `plan` says so once; the recap is kept until the session is confirmed, so a failed first turn and
            // "Try again" carry it again.
            if next.needsRecap {
                claudeRecap = ClaudeCodeRecap.text(turns: conversation.turns.dropLast().map { ($0.role, $0.text) })
            }
            // ponytail: the companion's prompt rides every turn, so a resumed session's history grows by it each turn; send it only when it changed if that cost ever shows.
            factory.claude = ClaudeCodeSetup(executable: state.claudeCodeStatus.executable ?? "", turn: next.turn,
                                             preamble: [Companion.claudePreambleHead + "\n"
                                                 + (firstSystem ?? parts.system(placement: AIPlacement.cloud.rawValue, provider: AIProviderID.claudeCode.rawValue)),
                                                 (next.turn.level == .chatOnly || next.turn.level == .noTools) ? nil : Companion.claudeToolsLine,
                                                 next.turn.resume ? nil : claudeRecap]
                                                 .compactMap { $0 }.joined(separator: "\n\n"))
            claudeFolder = next.turn.level.folder ?? chatFolder
        }
        let sessionFolder = claudeFolder
        #endif
        #if !APPSTORE
        if primary.provider == .codexPlan { factory.codex = codexSetup(quick: firstSystem != nil) }
        #endif
        let runFactory = factory
        let convo = conversation
        let notices = NoticeBox()
        let runner = ChatRunner(
            makeProvider: { runFactory.make($0) },
            makeRequest: { target in
                let details = await runFactory.details(target)
                let built = convo.request(model: target.model, api: AICatalog.info(target.provider).api,
                                          vision: details.vision, placement: target.placement,
                                          contextTokens: details.contextTokens,
                                          system: firstSystem ?? parts.system(placement: CompanionRightNow.contractPlacement(for: target.placement), provider: target.provider.rawValue),
                                          maxTokens: AICatalog.maxOutputTokens(for: target.placement),
                                          webSearch: firstSystem == nil && (target.provider == .anthropic || target.provider == .openai))
                notices.set(built)
                return built.request
            })
        let placeholder = ChatMessage(role: .assistant, content: "")
        let msgID = placeholder.id
        state.chatHistory.append(placeholder)
        state.chatStreaming = true

        let result = await runner.run(
            plan: plan, primary: primary,
            fallback: { await AIService.shared.freshLocalTarget(for: convo.feature) },
            onEvent: { event in
                await MainActor.run {
                    guard generation == ClaudeService.shared.conversationGeneration,
                          let i = state.chatHistory.firstIndex(where: { $0.id == msgID }) else { return }
                    switch event {
                    case .started:
                        state.chatHistory[i].content = ""
                        state.chatNotice = nil
                    case .text(let visible):
                        state.chatHistory[i].content = visible
                        if !visible.isEmpty {
                            state.stateOverride = nil
                            state.chatNotice = nil
                        }
                    case .citation(let c):
                        if !state.chatHistory[i].sources.contains(c) { state.chatHistory[i].sources.append(c) }
                    case .waking(let t):
                        state.chatNotice = ChatNotice(text: AIMessages.waking(t))
                        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.yawn)
                    case .fellBack(let from, let to, _):
                        state.chatHistory[i].notice = AIMessages.fellBack(from: from, to: to)
                    case .step(let step):
                        if let j = state.chatHistory[i].steps.firstIndex(where: { $0.id == step.id }) {
                            state.chatHistory[i].steps[j] = step
                        } else {
                            state.chatHistory[i].steps.append(step)
                        }
                    case .engine(let report):
                        #if !APPSTORE
                        state.claudeRunReport = report
                        // Claude Code has made the session: the next turn resumes it, from the same folder.
                        ClaudeService.shared.claudeSessionStarted(in: sessionFolder)
                        #endif
                    }
                }
            })
        guard generation == conversationGeneration else { return }
        finish(result, primary: primary, notices: notices, msgID: msgID, query: query, context: context,
               addedUserTurn: addedUserTurn, retries: retries, state: state)
    }

    private func finish(_ result: RunResult, primary: ChatTarget, notices: NoticeBox, msgID: UUID, query: String,
                        context: PromptContext?, addedUserTurn: Bool, retries: Int, state: AppState) {
        state.chatStreaming = false
        state.chatNotice = nil
        state.stateOverride = nil
        let i = state.chatHistory.firstIndex { $0.id == msgID }
        // A step that never finished (Stop, a crash) ends as stopped: no row stays "running".
        if let i { state.chatHistory[i].steps = ChatStep.endingUnfinished(state.chatHistory[i].steps) }
        func removePlaceholder() { if let i { state.chatHistory.remove(at: i) } }
        func takeBackUserTurn() { if addedUserTurn { conversation.removeLastUser() } }

        switch result.outcome {
        case .ok, .fallback, .interrupted:
            guard let i, let answeredBy = result.answeredBy, !result.text.isEmpty else {
                removePlaceholder()
                takeBackUserTurn()
                showError(AIMessages.error(AIError(kind: .server), target: primary).text, action: nil, state: state)
                return
            }
            conversation.addAssistant(result.text)
            state.chatHistory[i].notice = AIMessages.replyNotes(fellBack: state.chatHistory[i].notice,
                                                                built: notices.built, finish: result.finish)
            state.chatHistory[i].content = result.text
            state.chatHistory[i].sources = result.citations
            state.chatHistory[i].caption = AIMessages.caption(answeredBy)
            state.chatHistory[i].interrupted = result.outcome == .interrupted
            // The file names this reply's user message carried (never their text), then the chat is saved.
            if let u = state.chatHistory[..<i].lastIndex(where: { $0.role == .user }) {
                state.chatHistory[u].files = conversation.turns.last(where: { $0.role == .user })?.files.map(\.name) ?? []
            }
            storeCurrent(state: state)
            Companion.shared.recordSent(notices.built?.request)
            // The one-time cloud line, after the reply's own notice (on its own line).
            if let cloud = Companion.shared.cloudLine(for: answeredBy) {
                state.chatHistory[i].notice = [state.chatHistory[i].notice, cloud].compactMap { $0 }.joined(separator: "\n")
            }
            if answeredBy.placement != .cloud { state.lastUsedLocal = answeredBy.ref }
            state.view = .prompt
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
        case .cancelled:
            // Stop during Claude Code's work keeps the steps it took (stopped), even with no words yet.
            let keptSteps = i.map { !state.chatHistory[$0].steps.isEmpty } ?? false
            if result.text.isEmpty, !keptSteps {
                removePlaceholder()
                takeBackUserTurn()
            } else if result.text.isEmpty {
                // The steps stay on screen; the chat has nothing of Claude's to remember for this turn.
            } else {
                conversation.addAssistant(result.text)
                if let i {
                    state.chatHistory[i].content = result.text
                    // The partial reply says who wrote it and where its sources are, like a finished one (spec §4).
                    state.chatHistory[i].sources = result.citations
                    state.chatHistory[i].caption = result.answeredBy.map(AIMessages.caption)
                }
            }
        case .retryCountdown where ModelRouter.shouldAutoRetry(retries: retries):
            removePlaceholder()
            takeBackUserTurn()
            startCountdown(seconds: result.error?.retryAfter ?? 20, target: primary, state: state) {
                if addedUserTurn {
                    await self.chat(query: query, context: context, state: state, retries: retries + 1)
                } else {
                    await self.reply(query: query, context: context, addedUserTurn: false, retries: retries + 1, state: state)
                }
            }
        case .error where result.error?.kind == .refusal:
            guard let i else { return }
            let text = result.text.isEmpty ? AIMessages.error(AIError(kind: .refusal), target: primary).text : result.text
            conversation.addAssistant(text)
            state.chatHistory[i].content = text
            state.chatHistory[i].caption = result.answeredBy.map(AIMessages.caption)
        default:
            removePlaceholder()
            takeBackUserTurn()
            let (text, action) = AIMessages.error(result.error ?? AIError(kind: .server), target: primary)
            // The plan's limit is the cat's rate-limit look, not its error face.
            var cat = BotState.error
            #if !APPSTORE
            if result.error?.code == ClaudeCodeError.planLimit { cat = .ratelimit }
            // A run refused for its tools was stopped right after init: Claude Code may have recorded its session, so Try again
            // starts a fresh one (as a new conversation does), told the chat so far. The old id stays the chat's for a late hook
            // event of the killed run, as a quick action's does.
            if result.error?.code == ClaudeCodeError.toolsPresent {
                HookServer.shared.cancelChatApprovals()
                if quickClaudeSessions.count >= Self.quickSessionsMax { quickClaudeSessions.removeAll() }
                quickClaudeSessions.insert(claudeSession.reset())
                claudeRecap = ClaudeCodeRecap.text(turns: conversation.turns.map { ($0.role, $0.text) })
            }
            #endif
            showError(text, action: action, state: state, cat: cat)
        }
    }

    /// "Claude is busy. Trying again in 20 s.", then an automatic retry (up to `ModelRouter.maxAutoRetries`).
    private func startCountdown(seconds: Int, target: ChatTarget, state: AppState,
                                retry: @escaping @MainActor () async -> Void) {
        countdownTask = Task {
            for left in stride(from: seconds, to: 0, by: -1) {
                state.chatNotice = ChatNotice(text: AIMessages.countdown(target, seconds: left), cancellable: true)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { state.chatNotice = nil; return }
            }
            state.chatNotice = nil
            state.stateOverride = .thinking
            replyTask = Task { await retry() }
        }
    }

    #if !APPSTORE
    /// The chat's model choice names Claude Code explicitly (so its status is looked at even before it is connected).
    private func usesClaudeCodeByChoice() -> Bool {
        if case .explicit(let ref) = AppState.shared.choice(for: conversation.feature), ref.provider == .claudeCode { return true }
        return false
    }
    #endif

    /// A status answer is two rows: its question (a user row) and its answer (an assistant row with SidekickChat.caption). A question that such an answer follows is not a message the model answered.
    static func isStatusQuestion(_ rows: [ChatMessage], at i: Int) -> Bool {
        rows.indices.contains(i + 1) && rows[i + 1].role == .assistant && rows[i + 1].caption == SidekickChat.caption
    }

    /// "Try again" under a note: the last message is sent again. A status question is skipped: it was answered on this Mac, and it is not a message to send again.
    func resendLastMessage(state: AppState) {
        let rows = state.chatHistory
        guard !state.chatStreaming, let i = rows.indices.last(where: { rows[$0].role == .user && !Self.isStatusQuestion(rows, at: $0) }) else { return }
        let text = state.chatHistory[i].content
        state.chatHistory.remove(at: i)
        // "Try again" on a quick Explain that failed is still that first turn (its reply runs later, after this returns), so it keeps its own system text and level.
        let quick = quickFirst
        send(query: text, context: nil, state: state)
        quickFirst = quick
    }

    /// The partial reply's "Continue".
    func continueReply(state: AppState) {
        send(query: "Continue from where you stopped.", context: nil, state: state)
    }

    /// The partial reply's "Retry": drops that reply and answers the same user message again.
    /// It never removes a user message: it didn't add one. It never drops a status answer either: the reply it drops is the newest assistant row that is not one.
    func retryLast(state: AppState) {
        guard !state.chatStreaming, let lastUser = conversation.regenerate() else { return }
        if let i = state.chatHistory.lastIndex(where: { $0.role == .assistant && $0.caption != SidekickChat.caption }) { state.chatHistory.remove(at: i) }
        state.stateOverride = .thinking
        replyTask = Task {
            await reply(query: lastUser.text, context: nil, addedUserTurn: false, retries: 0, state: state)
        }
    }

    // MARK: - Quick actions (Fix, Rewrite, Explain: CompanionQuickRun)

    /// A quick Explain: a new chat whose first message is the request's user text (its selection inside <text> tags, or the screenshot attached), answered under
    /// the request's system text for that one turn. Follow-ups are normal companion turns.
    func explain(request: CompanionQuickRequest, image: PreparedFile?, state: AppState) {
        clearConversation(state: state)
        #if !APPSTORE
        // The chat is held at no tools until the user picks a level, so every follow-up of it stays there too (ClaudeQuickHold).
        state.claudeQuickHold = true
        #endif
        quickFirst = QuickFirstTurn(system: request.system, user: request.user)
        if let image { conversation.attach(image) }
        // The first message of a new chat, started as `send` starts one (the status answer is not asked: this text is a selection, not a question to the sidekick).
        conversationID = Companion.shared.store.newConversationId()
        state.chatHistory.append(ChatMessage(role: .user, content: request.user))
        state.stateOverride = .thinking
        replyTask = Task { await chat(query: request.user, context: nil, state: state) }
    }

    /// A quick action that stopped before it sent anything (a model that cannot see the screenshot): a new chat that shows the question and why nothing was sent.
    /// Display only: the model is told nothing of these two rows.
    func showUnsent(question: String, note: String, state: AppState) {
        clearConversation(state: state)
        state.chatHistory = [ChatMessage(role: .user, content: question), ChatMessage(role: .assistant, content: note)]
    }

    /// One turn for Fix or Rewrite, to the chat's routed brain, answered under the request's own system text. It reads and writes nothing of the chat: the reply
    /// comes back as a value for the card, and a reply the model cut at its limit comes back as a failure. With the Claude plan it is a fresh session at no tools
    /// (its text is untrusted), the system text as the preamble; its id stays known to the hook router (the
    /// set is capped), so a late hook event of the run is never a session of the island. For a quick Explain, follow-up turns of that chat stay at no tools until the user picks a level.
    func quickReply(_ request: CompanionQuickRequest, image: PreparedFile?) async -> (text: String?, error: AIError?, target: ChatTarget?) {
        let service = AIService.shared
        let state = AppState.shared
        #if !APPSTORE
        // Before the Claude plan is used: is Claude Code there, and signed in? (Never on a timer.)
        if !state.claudeCodeStatus.isReady, state.claudeCodeEnabled { await service.refreshClaudeStatus() }
        #endif
        #if !APPSTORE
        // Before a quick action on the OpenAI plan: is Codex there, and signed in? (Never on a timer.)
        if usesCodexByChoice(.chat), !state.codexStatus.isReady { await service.refreshCodexStatus() }
        #endif
        var input = service.routeInput(.chat)
        if ModelRouter.plan(input) == nil {
            _ = await service.freshLocalTarget(for: .chat)
            input = service.routeInput(.chat)
        }
        guard let plan = ModelRouter.plan(input) else { return (nil, nil, nil) }
        let primary = service.primaryTarget(plan)
        var factory = service.factory()
        #if !APPSTORE
        if primary.provider == .claudeCode {
            var session = ClaudeChatSession()
            // The quick turn runs with no tools, because its text is untrusted (a selection, a clipboard or a screenshot).
            session.level = .noTools
            session.model = ClaudeCodeModel(rawValue: primary.model) ?? state.claudeCodeModel
            let turn = session.plan(chatFolder: ClaudeCodeFolders.chatFolder()).turn
            factory.claude = ClaudeCodeSetup(executable: state.claudeCodeStatus.executable ?? "", turn: turn, preamble: request.system)
            if quickClaudeSessions.count >= Self.quickSessionsMax { quickClaudeSessions.removeAll() }
            quickClaudeSessions.insert(session.sessionID)
        }
        #endif
        #if !APPSTORE
        if primary.provider == .codexPlan { factory.codex = codexSetup(quick: true) }
        #endif
        let runFactory = factory
        let box = NoticeBox()
        let runner = ChatRunner(
            makeProvider: { runFactory.make($0) },
            makeRequest: { target in
                let details = await runFactory.details(target)
                var parts: [ChatRequest.Part] = []
                if let image {
                    parts += AttachmentPlan.parts(for: image, api: AICatalog.info(target.provider).api, vision: details.vision,
                                                  placement: target.placement, contextTokens: details.contextTokens).parts
                }
                parts.append(.text(request.user))
                let built = ChatRequest(model: target.model, system: request.system, messages: [ChatRequest.Message(role: .user, parts: parts)],
                                        maxTokens: AICatalog.maxOutputTokens(for: target.placement))
                box.set(Conversation.Built(request: built, fileNotices: [], droppedMessages: 0))
                return built
            })
        let result = await runner.run(plan: plan, primary: primary,
                                      fallback: { await AIService.shared.freshLocalTarget(for: .chat) },
                                      onEvent: { _ in })
        Companion.shared.recordSent(box.built?.request)
        switch result.outcome {
        case .ok, .fallback:
            // A reply cut at the model's limit would paste over a part of the text it never finished: it is shown as a failure.
            if result.finish == .length { return (nil, AIError(kind: .badRequest, message: AIMessages.cutOff), result.answeredBy ?? primary) }
            return (result.text, nil, result.answeredBy ?? primary)
        default:
            return (nil, result.error ?? AIError(kind: .server), result.answeredBy ?? primary)
        }
    }

    // MARK: - Structured search (M8 — window attach + web search)

    func search(query: String, context: PromptContext?, state: AppState) async {
        guard let key = apiKey, !key.isEmpty else {
            await showError("Anthropic API key missing. Open settings to configure it.", state: state)
            return
        }

        var userContent: [[String: Any]] = []
        switch context {
        case .window(let appName, let title, let url):
            var text = "App: \(appName)\nWindow title: \(title)"
            if let url = url { text += "\nURL: \(url)" }
            text += "\n\nRequest: \(query)"
            userContent.append(["type": "text", "text": text])
        case .file(let name, let fileURL):
            if let fileURL = fileURL, let fileBlock = readFileAsBlock(url: fileURL) {
                userContent.append(fileBlock)
            }
            userContent.append(["type": "text", "text": "File: \(name)\n\nRequest: \(query)"])
        case nil:
            userContent.append(["type": "text", "text": query])
        }

        let system = """
        You are an assistant built into the notch of a Mac. Reply in English, short and precise.
        Reply ONLY with valid JSON in this exact format:
        {"title":"...","items":[{"label":"...","detail":"...","url":"..."}],"note":"..."}
        Maximum 3 items. "url" is optional. "note" is optional.
        """

        let tools: [[String: Any]] = [
            ["type": AICatalog.anthropicWebSearchType(model: model), "name": AICatalog.WebSearch.anthropicName, "max_uses": 3]
        ]

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "tools": tools,
            "system": system,
            "messages": [["role": "user", "content": userContent]],
        ]

        do {
            let result = try await callAPI(body: body, key: key)
            await handleResult(result, state: state)
        } catch {
            await showError(error.localizedDescription, state: state)
        }
    }

    // MARK: - API call

    private func callAPI(body: [String: Any], key: String, beta: String? = nil) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if let beta { request.setValue(beta, forHTTPHeaderField: "anthropic-beta") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 45

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            // Parse Anthropic error format: {"type":"error","error":{"type":"…","message":"…"}}
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = json["error"] as? [String: Any],
               let errType = err["type"] as? String,
               let errMsg = err["message"] as? String {
                if errType == "not_found_error" {
                    let id = AppState.shared.claudeModel
                    throw NSError(domain: "Claude", code: 0,
                        userInfo: [NSLocalizedDescriptionKey:
                            "Model not found: \(id). Pick another one in Settings."])
                }
                throw NSError(domain: "Claude", code: 0,
                    userInfo: [NSLocalizedDescriptionKey: errMsg])
            }
            let msg = String(data: data, encoding: .utf8) ?? "unknown error"
            throw NSError(domain: "Claude", code: 0, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return data
    }

    // MARK: - Structured result handler

    private func handleResult(_ data: Data, state: AppState) async {
        // Extract text from Anthropic response (may contain tool_use / web_search_tool_result blocks)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let textBlock = content.first(where: { $0["type"] as? String == "text" }),
              let text = textBlock["text"] as? String else {
            await showError("Unexpected API response.", state: state)
            return
        }

        // Strip markdown code fences if present, then extract JSON object
        let cleanText: String
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            cleanText = String(text[start...end])
        } else {
            cleanText = text
        }

        // Try to parse as our JSON format
        if let resultData = cleanText.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any] {
            let title  = parsed["title"] as? String ?? "Result"
            let note   = parsed["note"] as? String
            var items: [ResultItem] = []
            if let rawItems = parsed["items"] as? [[String: Any]] {
                for item in rawItems.prefix(3) {
                    items.append(ResultItem(
                        label:  item["label"]  as? String ?? "",
                        detail: item["detail"] as? String ?? "",
                        url:    item["url"]    as? String
                    ))
                }
            }
            state.searchResult = SearchResult(title: title, items: items, note: note)
        } else {
            // Fallback: show raw text in 3-line chunks
            let lines = cleanText.components(separatedBy: "\n").filter { !$0.isEmpty }.prefix(3)
            state.searchResult = SearchResult(
                title: "Claude's response",
                items: lines.map { ResultItem(label: $0, detail: "", url: nil) },
                note: nil
            )
        }

        state.stateOverride = nil
        state.view = .result
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.proud)
    }

    private func showError(_ message: String, state: AppState) async {
        showError(message, action: nil, state: state)
    }

    private func showError(_ message: String, action: AIAction?, state: AppState, cat: BotState = .error) {
        state.stateOverride = cat
        state.noteMessage = message
        state.noteAction = action.map { NoteAction(message: message, action: $0) }
        state.view = .note
    }

    // MARK: - File content block builder

    private func readFileAsBlock(url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let ext = url.pathExtension.lowercased()
        let base64 = data.base64EncodedString()

        if ext == "pdf" {
            return ["type": "document", "source": ["type": "base64", "media_type": "application/pdf", "data": base64]]
        } else if ["jpg", "jpeg"].contains(ext) {
            return ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": base64]]
        } else if ext == "png" {
            return ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": base64]]
        } else if ext == "gif" {
            return ["type": "image", "source": ["type": "base64", "media_type": "image/gif", "data": base64]]
        } else if ext == "webp" {
            return ["type": "image", "source": ["type": "base64", "media_type": "image/webp", "data": base64]]
        } else {
            // Text/code — inline as text if <= 200 KB
            guard data.count <= 200_000,
                  let text = String(data: data, encoding: .utf8) else { return nil }
            return ["type": "text", "text": "File contents:\n\(text)"]
        }
    }
}

/// The request built for whichever model answered (notices to show under the reply).
private final class NoticeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var last: Conversation.Built?
    func set(_ b: Conversation.Built) { lock.withLock { last = b } }
    var built: Conversation.Built? { lock.withLock { last } }
}
