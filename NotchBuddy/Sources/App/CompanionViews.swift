import SwiftUI

// The chat's menu and its stored conversations (F3a-mac, Tasks 5, 7 and 8): ChatMenuButton (New chat, Conversations, Pop out and the quick actions), QuickResultCard and
// ExplainScreenshotChip (the quick actions' card and chip above the field), PoppedOutNote (what the island shows while the chat is in its window) and ConversationListPane (the saved conversations, newest first, pinned on top; rename, pin, delete, and Delete all behind one
// confirmation). Opening one is ClaudeService.open. Nothing here runs on a timer or watches a file: the list is the store's own published list.

/// The chat's ellipsis menu, in the model chip's capsule look, left of the Folder control.
struct ChatMenuButton: View {
    @ObservedObject var state: AppState
    let newChat: () -> Void
    /// True in the pop-out window, where the way out is back to the island.
    var inWindow = false
    /// The message field's text: Fix, Rewrite and Explain act on it when it has words, else on the clipboard's text, read when the item is chosen.
    var fieldText = ""
    /// Whether the clipboard holds an image, looked at (its types only) when the pointer reaches the menu: never watched.
    @State private var hasImage = false

    var body: some View {
        Menu {
            Button("New chat", action: newChat)
            Button("Conversations") { state.chatPane = .conversations }
            if inWindow {
                Button("Bring back to the island") { CompanionWindowController.shared.bringBack() }
            } else {
                Button("Pop out") { CompanionWindowController.shared.popOut() }
            }
            Divider()
            Button("Fix") { runQuick("fix") }
            Button("Rewrite") { runQuick("rewrite") }
            Button("Explain") { runQuick("explain") }
            Button("Explain the copied screenshot") { Companion.shared.quickClipboardImage() }
                .disabled(!hasImage)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(Color(hex: "#7B8089"))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        // On the Menu itself (a modifier inside a borderless Menu's label may never fire): the clipboard's types are looked at when the pointer reaches it.
        .onHover { inside in
            if inside { hasImage = CompanionQuickSource.pasteboardHoldsImage() }
        }
        .accessibilityLabel("Chat menu")
    }

    /// Fix, Rewrite or Explain on the field's words, else on the clipboard's string (read now, because the item was chosen, and only once its types have passed:
    /// a password manager's copy is never read). Nothing usable shows the fixed note in the chat and starts nothing. From here there is no source app to replace in.
    private func runQuick(_ kind: String) {
        let types = NSPasteboard.general.types?.map(\.rawValue) ?? []
        let clipboard = CompanionQuickSource.hasSkippedType(types) ? nil : NSPasteboard.general.string(forType: .string)
        guard let pick = CompanionQuickSource.pick(field: fieldText, pasteboard: clipboard, pasteboardTypes: types) else {
            AppState.shared.chatNotice = ChatNotice(text: CompanionQuickRules.noSelectionNote)
            return
        }
        Companion.shared.quick(kind: kind, text: pick.text, sourcePID: nil, fromClipboard: pick.fromClipboard)
    }
}

/// The Fix or Rewrite result, above the chat's field: the text (plain, selectable), a grey note when it was cut, Replace (only with a source app), Copy and a close button.
/// Replace puts the text on the pasteboard and brings the source app forward; the user pastes. Nothing here presses a key.
struct QuickResultCard: View {
    @ObservedObject var state: AppState
    let result: QuickResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if result.running { ProgressView().controlSize(.small).scaleEffect(0.7) }
                Text(result.heading)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(Color(hex: "#C8CDD4"))
                Spacer(minLength: 8)
                Button {
                    state.quickResult = nil
                    Companion.shared.cancelQuick()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color(hex: "#7B8089"))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            if !result.text.isEmpty {
                ScrollView(.vertical, showsIndicators: false) {
                    Text(verbatim: result.text)
                        .font(.system(size: 12.5))
                        .foregroundColor(Color(hex: "#F1F2F4"))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 48, maxHeight: 84)   // a real minimum: in a short chat the scroll must not collapse to nothing
            }
            if result.cut {
                Text(CompanionChrome.cutNote)
                    .font(.system(size: 10.5))
                    .foregroundColor(Color(hex: "#7B8089"))
            }
            if result.fromClipboard {
                Text(CompanionQuickRules.clipboardNote)
                    .font(.system(size: 10.5))
                    .foregroundColor(Color(hex: "#7B8089"))
            }
            if let note = result.note {
                Text(note)
                    .font(.system(size: 10.5))
                    .foregroundColor(Color(hex: "#7B8089"))
            }
            if result.canCopy {
                HStack(spacing: 8) {
                    if result.canReplace, let pid = result.sourcePID {
                        PrimaryButton("Replace") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(result.text, forType: .string)
                            if let app = NSRunningApplication(processIdentifier: pid) {
                                NSApp.yieldActivation(to: app)   // a cooperative hand-over, so the app comes forward even when this one is active
                                app.activate()
                            }
                            state.quickResult?.note = CompanionChrome.replaceNote
                        }
                    }
                    SecondaryButton("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(result.text, forType: .string)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .layoutPriority(1)   // the card keeps its size; the transcript above is the part that gives way
    }
}

/// The chip above the field while an image waits to go out with the next message: it asks for an explanation of that image.
struct ExplainScreenshotChip: View {
    let image: PreparedFile

    var body: some View {
        HStack(spacing: 0) {
            Button {
                Companion.shared.quick(kind: "explainImage", text: nil, image: image, sourcePID: nil)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "photo")
                        .font(.system(size: 9))
                    Text("Explain this screenshot")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .foregroundColor(Color(hex: "#C8CDD4"))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }
}

/// What the island's chat view shows while the chat is in its own window: one live chat only, so one text field and one focus.
struct PoppedOutNote: View {
    let state: AppState

    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: .indigo)
            VStack(alignment: .leading, spacing: 10) {
                Text(CompanionChrome.poppedOutNote)
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "#F1F2F4"))
                HStack(spacing: 8) {
                    PrimaryButton("Show the window") { CompanionWindowController.shared.popOut() }
                    SecondaryButton("Bring it back") { CompanionWindowController.shared.bringBack() }
                }
            }
            .padding(.leading, 84)   // the cat's gutter, as the chat's
            .padding(.trailing, 16)
        }
        .padding(.bottom, 10)
    }
}

/// The stored conversations, in the chat's pane. A tap opens one and shows the chat again.
struct ConversationListPane: View {
    @ObservedObject var state: AppState
    @ObservedObject private var store = Companion.shared.store
    @State private var renamingID: String?
    @State private var draft = ""
    @State private var confirmDeleteAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if state.chatStreaming {
                Text("Wait for the reply to finish to open a conversation.")
                    .font(.system(size: 10.5))
                    .foregroundColor(Color(hex: "#7B8089"))
            }
            if store.conversations.isEmpty {
                Text("No saved conversations yet.")
                    .font(.system(size: 10.5))
                    .foregroundColor(Color(hex: "#7B8089"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(store.conversations, id: \.id) { conversation in
                            row(conversation)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            HStack(spacing: 8) {
                SecondaryButton("Back to the chat") { state.chatPane = .chat }
                Spacer(minLength: 8)
                if !store.conversations.isEmpty {
                    Button("Delete all") { confirmDeleteAll = true }
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(Color(hex: "#7B8089"))
                        .buttonStyle(.plain)
                }
            }
        }
        .confirmationDialog("Delete all saved conversations?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Delete all", role: .destructive) { if store.deleteAll() == 0 { ClaudeService.shared.forgetAllStored() } }
        } message: {
            Text("Every saved conversation is deleted. This cannot be undone.")
        }
    }

    @ViewBuilder
    private func row(_ conversation: CompanionConversation) -> some View {
        HStack(spacing: 8) {
            if renamingID == conversation.id {
                TextField("Name", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .onSubmit {
                        store.rename(id: conversation.id, title: draft)
                        renamingID = nil
                    }
                    .onExitCommand { renamingID = nil }
            } else {
                Button {
                    guard CompanionChatRules.canOpen(streaming: state.chatStreaming, busy: state.stateOverride == .thinking) else { return }
                    ClaudeService.shared.open(conversationID: conversation.id, state: state)
                    state.chatPane = .chat
                } label: {
                    HStack(spacing: 6) {
                        if conversation.pinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 8))
                                .foregroundColor(Color(hex: "#7B8089"))
                        }
                        Text(conversation.title)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(Color(hex: "#F1F2F4"))
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text(CompanionChatRules.dayLabel(updatedAt: conversation.updatedAt, now: Int(Date().timeIntervalSince1970 * 1000),
                                                         calendar: .current))
                            .font(.system(size: 10.5))
                            .foregroundColor(Color(hex: "#7B8089"))
                    }
                    .contentShape(Rectangle())
                    .opacity(state.chatStreaming ? 0.5 : 1)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Rename") {
                        draft = conversation.title
                        renamingID = conversation.id
                    }
                    Button(conversation.pinned ? "Unpin" : "Pin") { store.setPinned(id: conversation.id, !conversation.pinned) }
                    Button("Delete", role: .destructive) { if store.delete(id: conversation.id) == 0 { ClaudeService.shared.forgetStored(id: conversation.id) } }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
