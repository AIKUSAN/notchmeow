import SwiftUI

// "What's Claude doing?" in the chat, answered on this Mac. The chat's send path asks `answer` FIRST and returns before it chooses a provider, touches the model's history or shows the typing dots, so a question
// like this one is never part of what a model is sent: the question and the answer go only into the chat's list on screen (`AppState.chatHistory`, which no provider reads: what a model is sent is the
// chat service's own history, which this file never reaches), and a dropped file's context is not reset. If the chat is on a cloud model, nothing about the question or its answer is sent anywhere.
// The words are the engine's (`SidekickEngine.status(for:)`, from the ledger); the local voice may reword them by the same rules as a recap, in the background, after the template is shown.

@MainActor
enum SidekickChat {
    /// The line under the answer, where a model's reply says "cloud · Claude Sonnet 5.5".
    static let caption = "From NotchMeow, on this Mac"
    /// The words of the chip in the chat's empty state.
    static let chipText = "What's Claude doing?"

    /// Answers `query` here when it is the status question (a whole short message), and returns true; otherwise nothing happens and it returns false, and the message is a normal one.
    @discardableResult
    static func answer(_ query: String, state: AppState = .shared, engine: SidekickEngine = Sidekick.shared.engine) -> Bool {
        guard let answered = engine.status(for: query) else { return false }
        state.chatHistory.append(ChatMessage(role: .user, content: query))
        var reply = ChatMessage(role: .assistant, content: SK.markdownPlain(answered.lines.joined(separator: "\n")))   // shown as Markdown: a file name is its own words
        reply.caption = caption
        state.chatHistory.append(reply)
        // A nicer sentence from a model on this computer, if there is one in time: it replaces the words once.
        if SidekickStore.shared.settings.local, !answered.facts.isEmpty {
            let id = reply.id
            Task { @MainActor in
                guard let nicer = await SidekickVoiceApp.nicer(lines: answered.lines, facts: answered.facts),
                      let i = state.chatHistory.firstIndex(where: { $0.id == id }) else { return }
                state.chatHistory[i].content = SK.markdownPlain(nicer)
            }
        }
        return true
    }
}

/// The chip in the chat's empty state: one tap asks the question. It shows only while an agent has a live session (there is something to answer); with none it is not drawn at all.
struct SidekickStatusChip: View {
    @ObservedObject var state: AppState
    /// The engine publishes its live agents, so the chip appears and goes by itself when an agent starts or its last session ends.
    @ObservedObject private var engine = Sidekick.shared.engine

    @ViewBuilder var body: some View {
        if !engine.liveAgents.isEmpty {
        Button { SidekickChat.answer(SidekickChat.chipText, state: state) } label: {
            HStack(spacing: 5) {
                Image(systemName: "sparkles").font(.system(size: 8)).foregroundColor(Color(hex: "#5C6370"))
                Text(SidekickChat.chipText)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(Color(hex: "#7B8089"))
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        }
    }
}
