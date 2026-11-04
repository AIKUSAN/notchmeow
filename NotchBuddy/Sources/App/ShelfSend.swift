import AppKit

// Send (sub-project G1): the standard share picker (`NSSharingServicePicker`) and a one-click AirDrop button (`NSSharingService(named: .sendViaAirDrop)`). Sending always starts with a click,
// and the system's sheet keeps the recipients private from NotchMeow: the log says only that a send started, never names or recipients. While the picker or the AirDrop window is up the island
// stays open (`AppState.sharePickerSince`, a clock reading with a limit: `ShelfHold`), and for 15 s after a share ran (`ShelfHold.afterSendLinger`, the same reading rewound: the one timer in
// `IslandWindowController`, armed for `ShelfHold.releaseDelay`, sees the end). Each item is opened (`ShelfStore.open`) until the share is over, so a security-scoped original stays readable. The island is a panel that
// never activates, so it takes the key for the picker the way the chat does for its text field.

@MainActor
final class ShelfSend {
    static let shared = ShelfSend()

    private var accesses: [ShelfAccess] = []
    /// The callbacks of the share that is under way, and only of it: the picker and the service hold their delegate weakly, so a share that is over or replaced loses its delegate, and anything it
    /// still calls is ignored (`ShelfShareDelegate.isCurrent`).
    fileprivate var shareDelegate: ShelfShareDelegate?
    private var state: AppState { AppState.shared }

    /// Opens the items for the share. Nil when any of them has gone missing (the buttons are off for that, this is the second line).
    private func begin(_ items: [ShelfItem], model: ShelfModel) -> [URL]? {
        finish()
        let opened = items.compactMap { model.open($0) }
        guard opened.count == items.count, !opened.isEmpty else {
            for a in opened { a.end() }
            return nil
        }
        accesses = opened
        shareDelegate = ShelfShareDelegate(owner: self)
        state.sharePickerSince = ProcessInfo.processInfo.systemUptime
        appendAppLog("shelf.log", "a send started")
        return opened.map(\.url)
    }

    /// The share is over: the files are closed and the picker's hold is cleared. After a service that ran (`lingering`), the island stays open for the linger, counted from now; a share that failed,
    /// was cancelled, or never started lets go at once.
    func finish(lingering: Bool = false) {
        let ran = lingering && !accesses.isEmpty
        shareDelegate = nil
        for a in accesses { a.end() }
        accesses = []
        if ran {
            state.sharePickerSince = ShelfHold.lingerSince(now: ProcessInfo.processInfo.systemUptime)
        } else {
            state.sharePickerSince = nil
        }
    }

    /// The share picker, below the island. The island's panel takes the key first.
    func showPicker(_ items: [ShelfItem], model: ShelfModel) {
        guard ShelfActionRules.canSend(items, missing: model.missing), let urls = begin(items, model: model) else { return }
        guard let panel = NSApp.windows.first(where: { $0 is IslandPanel }) as? IslandPanel, let content = panel.contentView else { finish(); return }
        panel.makeKey()
        let picker = NSSharingServicePicker(items: urls)
        picker.delegate = shareDelegate
        // A 2 pt rectangle just under the island's bottom edge, at its centre. The content view is not flipped, so `.minY` is the bottom.
        let island = panel.currentIslandFrame(nw: panel.notchWidth, nh: panel.notchHeight)
        let anchor = NSRect(x: island.midX - 1, y: island.minY - 2, width: 2, height: 2)
        picker.show(relativeTo: anchor, of: content, preferredEdge: .minY)
    }

    /// AirDrop in one click. When this Mac cannot AirDrop these items, the picker is the way to send them, and says nothing here.
    func airDrop(_ items: [ShelfItem], model: ShelfModel) {
        guard ShelfActionRules.canSend(items, missing: model.missing), let urls = begin(items, model: model) else { return }
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else { finish(); return }
        service.delegate = shareDelegate
        service.perform(withItems: urls)
    }
}

/// One share's callbacks. A service that is still running when a newer share begins (an AirDrop transfer) must not close the newer share's files or replace its hold, so every callback first asks
/// whether this is still the current share.
@MainActor
fileprivate final class ShelfShareDelegate: NSObject, @MainActor NSSharingServicePickerDelegate, @MainActor NSSharingServiceDelegate {
    unowned let owner: ShelfSend
    init(owner: ShelfSend) { self.owner = owner }

    private var isCurrent: Bool { owner.shareDelegate === self }
    private func finish(lingering: Bool = false) { if isCurrent { owner.finish(lingering: lingering) } }

    // MARK: NSSharingServicePickerDelegate

    func sharingServicePicker(_ picker: NSSharingServicePicker, delegateFor service: NSSharingService) -> NSSharingServiceDelegate? { self }

    /// `service` is nil when the picker closed without a choice.
    func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        if service == nil { finish() }
    }

    // MARK: NSSharingServiceDelegate

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) { finish(lingering: true) }
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) { finish() }
}
