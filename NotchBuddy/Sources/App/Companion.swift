import Foundation

// The companion in every turn (F3a-mac, Task 4): what the model is told at each turn (the cat and its traits, the quiet rule, the mood, the humor, "Right now"
// only while See my sessions is on and the cloud notice is not due, and today's date), the one-time cloud line per provider, and the lines of the last
// request, kept in memory only. The rules are in CompanionPrompt, CompanionRightNow and CompanionTurn; this file reads the app's state. Nothing here logs,
// and nothing runs on a timer.

@MainActor
final class Companion {
    static let shared = Companion()

    /// The head of a Claude Code turn's preamble: the companion's prompt rides in the user line the Claude Code process is given.
    static let claudePreambleHead = "From NotchMeow, the app this chat runs in (instructions and context for you, not words of the user):"

    #if !APPSTORE
    /// One fixed line after the prompt, on every Claude turn at Read-only and Agent: the prompt's conduct text says the companion cannot act on the Mac, which is about
    /// NotchMeow and must not be read as taking away the tools Claude Code gives at those levels. Not part of the contract's prompt (`promptOf` is untouched).
    static let claudeToolsLine = "In this chat you may use the tools Claude Code gives you in the folder the user chose; the sentence above about not acting on the Mac is about NotchMeow itself, not about your tools."
    #endif

    /// The store is read when `shared` is first used, never at launch.
    let store = CompanionStore.shared

    /// The lines the last request sent (`CompanionTurn.sentLines`). Memory only: never written, never logged. A reply that sent nothing keeps the last value.
    private(set) var lastSent: [String] = []

    /// The latest quick action (CompanionQuickRun): a run that was overtaken, or whose card was closed, lands late and is dropped. Memory only.
    var quickGate = QuickGate()
    var quickTask: Task<Void, Never>?

    /// The turn's parts, read now: the Main cat's name and traits, the user's first name, the quiet rule, the cat's own mood (the focused task's state, without
    /// the chat's own "thinking" override), humor and See my sessions, "Right now" from one Projects view, the cloud notices already shown, and today's date.
    func turnParts() -> CompanionTurnParts {
        let cats = CatSettingsStore.shared.settings
        let view = ProjectsModel.shared.view()
        var input = CompanionPromptInput()
        input.catName = CatPresets.all[cats.character]?.label
        input.userName = resolveUserFirstName()
        input.personality = cats.cats[cats.character]?.personality.traits ?? [:]
        input.humor = store.settings.humor
        input.quiet = quietNow(view: view)
        input.mood = (AppState.shared.focusTask?.state ?? .idle).rawValue
        input.seeSessions = store.settings.seeSessions
        if store.settings.seeSessions { input.rightNow = CompanionRightNow.text(view) }
        input.today = CompanionTurn.today(Date(), timeZone: .current)
        return CompanionTurnParts(input: input, cloudNoticeShown: store.settings.cloudNoticeShown)
    }

    /// The quiet rule: a session waits for the user (a stepped-back wait counts, as it is in the Projects view), or an approval or a question card is up.
    /// `view` is the Projects view already read for this turn; without one, the view is read now.
    func quietNow(view: PJView? = nil) -> Bool {
        let waiting = (view ?? ProjectsModel.shared.view()).waiting
        return CompanionPrompt.quiet(waiting: waiting,
                                     card: AppState.shared.pendingApproval != nil || AppState.shared.pendingQuestion != nil)
    }

    /// The one-time line before a cloud brain first gets "Right now": the provider is recorded so the line is not shown again. Nil when there is nothing to say.
    /// It is asked for only after a reply has landed, so a refused or cancelled turn records nothing.
    func cloudLine(for target: ChatTarget) -> String? {
        let settings = store.settings
        let provider = target.provider.rawValue
        guard CompanionRightNow.needsCloudNotice(placement: CompanionRightNow.contractPlacement(for: target.placement), seeSessions: settings.seeSessions,
                                                 provider: provider, shown: settings.cloudNoticeShown)
        else { return nil }
        store.update { $0.cloudNoticeShown.append(provider) }
        return CompanionRightNow.cloudNotice(provider: CompanionRightNow.noticeName(provider: target.provider, displayName: ChatProvider(target.provider).displayName))
    }

    /// Delete all also forgets what the last request sent: it holds the text of the conversations that were just deleted.
    func clearSent() {
        lastSent = []
    }

    /// Keeps the lines a request sent. Nil (a reply that sent no request) keeps the last value.
    func recordSent(_ request: ChatRequest?) {
        guard let request else { return }
        lastSent = CompanionTurn.sentLines(request)
    }
}

extension CatPersonality {
    /// The six traits the companion's prompt reads, by the contract's names.
    var traits: [String: Double] {
        ["energy": energy, "curiosity": curiosity, "chatty": chatty, "affection": affection, "sass": sass, "mischief": mischief]
    }
}
