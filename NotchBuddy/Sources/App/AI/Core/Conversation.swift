import Foundation

/// What the model sees of one chat, independent of any provider. Files join the user message
/// they were attached before, and stay in the history after it; each provider gets them in its own
/// form (native PDF, image, or text cut to its budget).
struct Conversation: Sendable, Equatable {
    struct Turn: Sendable, Equatable {
        var role: ChatRequest.Role
        var text: String
        var files: [PreparedFile] = []
        /// "Context — App: …" line for an attached window.
        var context: String? = nil
    }

    private(set) var turns: [Turn] = []
    private(set) var pendingFiles: [PreparedFile] = []
    private(set) var pendingContext: String? = nil

    /// File questions (`files`) when the message being sent carries a file or any earlier message in this
    /// conversation did; otherwise `chat`. A file's text stays in the history, so a follow-up on the Chat
    /// route could send it to a cloud model that the person kept File questions away from. Derived from the
    /// messages, never from a flag. A file drop or an attached window starts a new `Conversation`, which
    /// resets it. Continue and Retry add no file, so they keep the route of the reply they follow.
    var feature: AIFeature {
        let carriesFile = !pendingFiles.isEmpty || turns.contains { !$0.files.isEmpty }
        return carriesFile ? .files : .chat
    }

    /// The file goes out with the next user message, whichever turn that is.
    mutating func attach(_ file: PreparedFile) { pendingFiles.append(file) }

    mutating func attachContext(_ line: String) { pendingContext = line }

    mutating func addUser(_ text: String) {
        turns.append(Turn(role: .user, text: text, files: pendingFiles, context: pendingContext))
        pendingFiles = []
        pendingContext = nil
    }

    /// Empty replies are not kept (APIs reject empty assistant messages).
    mutating func addAssistant(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        turns.append(Turn(role: .assistant, text: t))
    }

    /// Undo a user message that got no answer, putting its files back for the next try.
    mutating func removeLastUser() {
        guard let last = turns.last, last.role == .user else { return }
        turns.removeLast()
        pendingFiles = last.files + pendingFiles
        pendingContext = last.context ?? pendingContext
    }

    /// Retry: drops the last answer and hands back the user message it answered, so it can be answered
    /// again. Only an answer is ever removed, and only when the chat ends with a user message and its
    /// answer: a message still being answered, or an earlier exchange, is left alone. Retry never takes
    /// back a user message, because it didn't add one.
    mutating func regenerate() -> Turn? {
        guard turns.count >= 2, turns[turns.count - 1].role == .assistant,
              turns[turns.count - 2].role == .user else { return nil }
        turns.removeLast()
        return turns.last
    }

    struct Built: Sendable, Equatable {
        var request: ChatRequest
        /// Truncation notices for the newest message's files ("I read the first 716 lines.").
        var fileNotices: [String]
        var droppedMessages: Int
    }

    /// The request for one model.
    func request(model: String, api: AIProviderAPI, vision: Bool, placement: AIPlacement, contextTokens: Int?,
                 system: String, maxTokens: Int, webSearch: Bool) -> Built {
        var notices: [String] = []
        var messages: [ChatRequest.Message] = turns.enumerated().map { index, turn in
            var parts: [ChatRequest.Part] = []
            if let context = turn.context { parts.append(.text(context)) }
            for file in turn.files {
                let planned = AttachmentPlan.parts(for: file, api: api, vision: vision,
                                                   placement: placement, contextTokens: contextTokens)
                parts += planned.parts
                // Only the newest message's notices are new to the user.
                if index == turns.count - 1, let n = planned.notice { notices.append(n) }
            }
            parts.append(.text(turn.text))
            return ChatRequest.Message(role: turn.role, parts: parts)
        }
        // A failed Retry leaves its question unanswered; if the user then asks something else, two user
        // messages follow each other. Some chat templates refuse that, so same-role neighbours are joined.
        messages = Self.joiningSameRole(messages)
        // Long chats on small models: the shared rule (history-cases.json), in Unicode scalars.
        let trim = ContextBudget.trimHistory(messages: messages, system: system, placement: placement,
                                             contextTokens: contextTokens)
        messages.removeFirst(trim.dropped)
        let request = ChatRequest(model: model, system: system, messages: messages, maxTokens: maxTokens,
                                  webSearch: webSearch)
        return Built(request: request, fileNotices: notices, droppedMessages: trim.dropped)
    }

    private static func joiningSameRole(_ messages: [ChatRequest.Message]) -> [ChatRequest.Message] {
        var joined: [ChatRequest.Message] = []
        for message in messages {
            if let last = joined.last, last.role == message.role {
                joined[joined.count - 1].parts += message.parts
            } else {
                joined.append(message)
            }
        }
        return joined
    }
}
