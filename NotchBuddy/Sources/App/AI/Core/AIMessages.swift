import Foundation

/// The one button a message may carry.
enum AIAction: Sendable, Equatable {
    case openSettings
    case openBilling(URL)
    case openGuide
    case chooseModel
    /// Claude Code: open Terminal to sign in, show Anthropic's install page, show its update page, show Git for
    /// Windows' page, or send the last message again.
    case signInClaude, installClaude, updateClaude, installGit, tryAgain
    /// Codex: show the install guide or the update guide (the same page, `CodexLocator.installGuide`).
    case installCodex, updateCodex
}

/// Every user-facing AI string (spec §5 copy table). Plain, lightly cat-flavoured, one action at most.
enum AIMessages {
    static let historyTrimmed = ContextBudget.historyNotice
    static let outOfRoom = "The model ran out of room before answering. Try again, or pick a model without thinking mode."
    static let cutOff = "The answer was cut off."
    static let interrupted = "interrupted"
    static let localGuide = "Run a model on this Mac with [Ollama](https://ollama.com/download) or "
        + "[LM Studio](https://lmstudio.ai), then come back. I'll find it on my own."
    static let emptyStateTitle = "Pick a brain for me first."

    /// "Claude", "OpenAI", "Gemini", "Apple's model", or a local model's family ("Qwen").
    static func shortName(_ t: ChatTarget) -> String {
        switch t.provider {
        case .anthropic, .claudeCode: return "Claude"
        case .openai, .codexPlan: return "OpenAI"
        case .google: return "Gemini"
        case .apple: return "Apple's model"
        default:
            let base = t.model.split(separator: "/").last.map(String.init) ?? t.model
            let letters = base.prefix { $0.isLetter }
            return letters.isEmpty ? base : letters.prefix(1).uppercased() + letters.dropFirst()
        }
    }

    /// Model ID without its tag: "qwen3.5:2b" → "qwen3.5".
    static func bareModel(_ model: String) -> String {
        String(model.split(separator: ":").first ?? Substring(model))
    }

    static func serverName(_ t: ChatTarget) -> String {
        t.provider == .custom ? (t.host ?? "the local server") : AICatalog.info(t.provider).name
    }

    /// Caption under each reply: `cloud · Claude Sonnet 5.5`, `local · qwen3.5:2b`, `network · llama3 @ studio-pc`.
    static func caption(_ t: ChatTarget) -> String {
        let name = t.provider == .apple ? "Apple on-device" : (t.modelLabel ?? t.model)
        if t.placement == .network, let host = t.host { return "network · \(name) @ \(host)" }
        return "\(t.placement.rawValue) · \(name)"
    }

    /// The drop card's line: "Claude will read this", "Local · qwen3.5:2b will read this".
    static func dropReader(_ t: ChatTarget?) -> String? {
        guard let t else { return nil }
        switch t.placement {
        case .cloud: return "\(shortName(t)) will read this"
        case .local: return t.provider == .apple ? "Apple on-device will read this" : "Local · \(short(t.model)) will read this"
        case .network: return "Network · \(short(t.model)) @ \(t.host ?? "server") will read this"
        }
    }

    /// Settings and picker label: "Claude Sonnet 5.5", "OpenAI · gpt-6.1-sol", "Local · qwen3.5:2b".
    static func targetLabel(_ t: ChatTarget) -> String {
        switch t.placement {
        case .cloud: return t.modelLabel ?? "\(shortName(t)) · \(t.model)"
        case .local: return t.provider == .apple ? "Apple on-device" : "Local · \(t.model)"
        case .network: return "Network · \(t.model) @ \(t.host ?? "server")"
        }
    }

    #if !APPSTORE
    /// The button under a Claude Code note, as the app's own action.
    static func action(for action: ClaudeCodeText.Note.Action) -> AIAction {
        switch action {
        case .installGuide: .installClaude
        case .signIn: .signInClaude
        case .updateGuide: .updateClaude
        case .retry: .tryAgain
        case .gitGuide: .installGit
        }
    }
    #endif

    /// Drop card line for a file the AI can't take.
    static func rejected(_ reason: AttachmentRejection) -> String {
        switch reason {
        case .size: "Over 25 MB: too big for me to read, but I can email it."
        case .type: "I can't read this kind of file, but I can email it."
        }
    }

    /// Long model IDs (`hf.co/…/Qwen3.5-2B-GGUF:Q4_K_M`) keep their start and end.
    static func short(_ model: String, max: Int = 28) -> String {
        guard model.count > max else { return model }
        return model.prefix(max / 2 - 1) + "…" + model.suffix(max / 2)
    }

    static func fellBack(from: ChatTarget, to: ChatTarget) -> String {
        "\(shortName(from))'s busy right now, so \(shortName(to)) answered instead."
    }

    static func countdown(_ t: ChatTarget, seconds: Int) -> String {
        "\(shortName(t)) is busy. Trying again in \(seconds) s."
    }

    static func waking(_ t: ChatTarget) -> String { "Waking up \(bareModel(t.model))…" }

    /// The message (and its one action) for a failed reply.
    static func error(_ e: AIError, target t: ChatTarget) -> (text: String, action: AIAction?) {
        #if !APPSTORE
        if t.provider == .claudeCode, let note = ClaudeCodeText.message(for: e) {
            return (note.text, note.action.map(action(for:)))
        }
        if t.provider == .codexPlan, let note = CodexText.message(for: e) { return note }
        #endif
        let name = shortName(t)
        let local = t.placement != .cloud
        if e.code == AIError.outOfRoomCode { return (outOfRoom, .chooseModel) }
        switch e.kind {
        case .auth:
            let owner = t.provider.isCloud ? AICatalog.info(t.provider).name : serverName(t)
            return ("Your \(owner) key was rejected.", .openSettings)
        case .billing:
            let owner = AICatalog.info(t.provider).name
            let text = HTTPErrorRules.isSpendLimit(e.code) ? "Your \(owner) spend limit was reached."
                                                            : "Your \(owner) credit ran out."
            return (text, billingURL(t.provider).map(AIAction.openBilling))
        case .unreachable where local:
            return ("Couldn't reach \(serverName(t)). Is its server on?", .openGuide)
        case .unreachable:
            return ("Couldn't reach \(name). Check your connection.", nil)
        case .offline:
            return ("You're offline, and no local model is ready.", .openGuide)
        case .timeout:
            return ("\(local ? bareModel(t.model) : name) took too long to answer.", nil)
        case .server:
            return ("\(local ? serverName(t) : name) had a problem. Try again in a moment.", nil)
        case .rateLimited, .overloaded:
            return ("\(name) is still busy. Try again in a moment.", nil)
        case .badRequest where e.status == 404:
            return local ? ("\(t.model) isn't installed. Pick another model above the chat box.", .chooseModel)
                         : ("Model not found: \(t.model). Pick another one in Settings.", .openSettings)
        case .badRequest:
            return (e.message ?? "\(name) couldn't handle that message.", nil)
        case .refusal:
            return ("\(name) declined to answer this.", nil)
        case .cancelled, .interrupted:
            return ("", nil)
        }
    }

    /// A cloud model-list call that failed (Settings' key check, the chat picker). Only an auth failure, an
    /// HTTP 400 (Google's answer to a bad key; chat still classes it `bad_request`) or an empty list means the
    /// key was refused; offline and unreachable never do, whatever the monitor says.
    static func listFailure(_ e: AIError?, provider: AIProviderID, online: Bool) -> (text: String, rejected: Bool) {
        let target = ChatTarget(provider: provider, model: "", placement: .cloud)
        guard let e else { return ("\(AICatalog.info(provider).name) didn't accept this key.", true) }
        if !online || e.kind == .offline || e.kind == .unreachable {
            return (error(AIError(kind: .unreachable), target: target).text, false)
        }
        if e.kind == .auth || e.status == 400 { return ("\(AICatalog.info(provider).name) didn't accept this key.", true) }
        return (error(e, target: target).text, false)
    }

    /// The quiet line under a reply: fell back to a local model, a file read in part, old messages dropped,
    /// an answer cut at the token cap. Nil when there is nothing to say.
    static func replyNotes(fellBack: String?, built: Conversation.Built?, finish: FinishReason?) -> String? {
        var notes = fellBack.map { [$0] } ?? []
        if let built {
            notes += built.fileNotices
            if built.droppedMessages > 0 { notes.append(historyTrimmed) }
        }
        if finish == .length { notes.append(cutOff) }
        return notes.isEmpty ? nil : notes.joined(separator: " ")
    }

    static func billingURL(_ provider: AIProviderID) -> URL? {
        switch provider {
        case .openai: URL(string: "https://platform.openai.com/settings/organization/billing/overview")
        case .anthropic: URL(string: "https://console.anthropic.com/settings/billing")
        case .google: URL(string: "https://aistudio.google.com/")
        default: nil
        }
    }
}
