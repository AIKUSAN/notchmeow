import AppKit
import ImageIO

// The quick actions' run (F3a-mac, Task 8): Fix and Rewrite from any app (Services) or from the chat's menu, Explain, and Explain this screenshot. The text is data:
// CompanionQuick wraps it in <text> tags (cut at 8,000 code points, every text tag defused) before a brain sees it, and a model's reply is only ever shown as plain
// text and put on the pasteboard by an explicit click. Nothing here posts a key, asks for Accessibility or watches the pasteboard: Replace is the card's button that
// copies the result and brings the source app forward, and the user pastes. Nothing is logged, nothing waits on a timer, and the main actor is free while a reply streams.

extension Companion {
    /// One quick action. `text` is the selection (Services) or the field's / clipboard's text (the chat's menu); nil text, or text with nothing in it, does nothing.
    /// `sourcePID` is the app the selection came from, for Replace. `fromClipboard` labels a card whose text the clipboard gave (the chat's menu only).
    func quick(kind: String, text: String?, image: PreparedFile? = nil, sourcePID: pid_t?, fromClipboard: Bool = false) {
        let cap = text.map(CompanionQuickSource.capped)
        let text = cap?.text
        guard let request = CompanionQuick.request(kind: kind, text: text) else { return }
        let cut = request.cut || cap?.cut == true
        let state = AppState.shared
        // A run that starts clears the "Select some text first." an empty menu action left: it would sit under the card until the next send.
        if CompanionQuickRules.clearsNotice(state.chatNotice?.text) { state.chatNotice = nil }
        quickTask?.cancel()
        let run = quickGate.begin()
        openChat(state)
        if kind == "fix" || kind == "rewrite" {
            state.quickResult = QuickResult.started(kind: kind, cut: cut, sourcePID: sourcePID, fromClipboard: fromClipboard)
            quickTask = Task {
                let answer = await ClaudeService.shared.quickReply(request, image: nil)
                guard quickGate.isCurrent(run), let card = state.quickResult else { return }
                if let reply = answer.text {
                    state.quickResult = card.finished(text: CompanionQuick.resultClean(kind: kind, reply: reply))
                } else if let error = answer.error, let target = answer.target {
                    state.quickResult = card.failed(AIMessages.error(error, target: target).text)
                } else {
                    state.quickResult = card.failed(AIMessages.emptyStateTitle)
                }
            }
            return
        }
        // Explain and Explain this screenshot: a new chat whose first turn is answered under the quick system text.
        guard kind != "explainImage" || image != nil else { return }
        state.quickResult = nil
        quickTask = Task {
            // A screenshot goes only to a model that can see it (the File questions route, as any image does); otherwise nothing is sent.
            let service = AIService.shared
            if kind == "explainImage", let target = service.resolve(.files).primary, await !service.factory().details(target).vision {
                guard quickGate.isCurrent(run) else { return }
                ClaudeService.shared.showUnsent(question: request.user, note: CompanionQuick.noVision, state: state)
                return
            }
            guard quickGate.isCurrent(run) else { return }
            ClaudeService.shared.explain(request: request, image: image, state: state)
            // explain() clears the chat's notice, so the clipboard label is set after it. It is a chat note: the chat clears its notice when the reply starts.
            if fromClipboard { state.chatNotice = ChatNotice(text: CompanionQuickRules.clipboardNote) }
        }
    }

    /// "Explain the copied screenshot": the clipboard's image, read now (the user chose the item), made small off the main actor, then explained.
    func quickClipboardImage() {
        let pasteboard = NSPasteboard.general
        // The types decide first: a copy a password manager marked is never read, not even to be refused. Nil data ends in the same noImageNote as a bad image.
        let types = pasteboard.types?.map(\.rawValue) ?? []
        let data = CompanionQuickSource.holdsReadableImage(types) ? (pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff)) : nil
        quickTask?.cancel()
        let run = quickGate.begin()
        AppState.shared.quickResult = nil   // an older Fix or Rewrite card was just overtaken: it would sit on "Fixing…" for good
        quickTask = Task {
            let image = await Task.detached(priority: .userInitiated) { data.flatMap { CompanionQuickSource.preparedImage(from: $0) } }.value
            guard quickGate.isCurrent(run) else { return }
            if let image {
                quick(kind: "explainImage", text: nil, image: image, sourcePID: nil)
            } else {
                openChat(AppState.shared)
                ClaudeService.shared.showUnsent(question: "Explain this screenshot.", note: CompanionQuickRules.noImageNote, state: AppState.shared)
            }
        }
    }

    /// The card was closed: whatever is still running for it is dropped.
    func cancelQuick() {
        quickTask?.cancel()
        quickGate.invalidate()
    }

    /// Shows the chat: the pop-out window if the chat is there, else the island on its chat view. Never over a card that waits for an answer.
    private func openChat(_ state: AppState) {
        if state.chatPoppedOut {
            CompanionWindowController.shared.popOut()
            return
        }
        state.chatPane = .chat
        guard state.pendingApproval == nil, state.pendingQuestion == nil else { return }
        if state.mode == .expanded {
            state.view = .prompt
        } else {
            NotificationCenter.default.post(name: .hookExpand, object: IslandView.prompt)
        }
    }
}

extension CompanionQuickSource {
    /// Whether the general pasteboard holds an image, by its types alone: no content is read.
    static func pasteboardHoldsImage() -> Bool {
        holdsReadableImage(NSPasteboard.general.types?.map(\.rawValue) ?? [])
    }

    /// The clipboard's image as a file for the model: its long edge at most 1,568 px (as a PDF page is), re-encoded as PNG, nothing kept of the original. Nil when it
    /// is over the file limit or is not an image. Slow on a big image: call it off the main actor.
    static func preparedImage(from data: Data) -> PreparedFile? {
        guard data.count <= AICatalog.Limits.maxFileBytes, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: AttachmentExtractor.pageImageLongEdge]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return nil }
        return PreparedFile(name: "Screenshot.png", kind: .image, mime: "image/png", data: png)
    }
}
