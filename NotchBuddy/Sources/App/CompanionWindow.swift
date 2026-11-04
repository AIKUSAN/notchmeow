import AppKit
import SwiftUI

// The chat's own window (F3a-mac, Task 7). One NSWindow, made once, hosting the same PromptView the island shows, on the app's one AppState (`inWindow: true`: no cat gutter,
// no card wash). While it is open the island's chat view shows PoppedOutNote instead (`AppState.chatPoppedOut`), so two live chat views never share a text field. Closing the
// window (its button, ⌘W, the menu's Bring back to the island) puts the chat back in the island; a reply that is streaming goes on (it lives in ClaudeService, not in the view).
// No timer, no observer and no work of its own: the window does nothing until it is shown.

@MainActor
final class CompanionWindowController: NSWindowController, NSWindowDelegate {
    static let shared = CompanionWindowController()

    private init() {
        super.init(window: Self.makeWindow())
        window?.delegate = self
    }

    required init?(coder: NSCoder) { nil }

    private static func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "Chat"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 420, height: 360)
        // The chat's colours are the island's light-on-dark ones, so the window is dark whatever the system is.
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(srgbRed: 20 / 255, green: 21 / 255, blue: 24 / 255, alpha: 1)
        let host = NSHostingView(rootView: PromptView(state: .shared, inWindow: true))
        host.sizingOptions = []   // the window's size is the user's (and the autosaved one), never the chat's content
        window.contentView = host
        window.center()   // the first time only: a saved frame, applied next, wins
        window.setFrameAutosaveName("NotchMeowChat")
        return window
    }

    /// Shows the chat window (or brings it forward), and folds the island so it cannot cover it.
    func popOut() {
        guard let window else { return }
        AppState.shared.chatPoppedOut = true
        NotificationCenter.default.post(name: .islandCollapse, object: nil)
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Closes the window; the chat is the island's again (`windowWillClose`).
    func bringBack() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        AppState.shared.chatPoppedOut = false
    }
}
