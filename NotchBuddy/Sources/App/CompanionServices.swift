import AppKit

// The companion's Services (F3a-mac, Task 8): "Fix with NotchMeow", "Rewrite with NotchMeow" and "Explain with NotchMeow" in the Services menu of any app that
// has a text selection. The OS calls these methods on the main thread, and the source app waits until they return, so each one only reads what the OS handed it
// (the selected text, and which app is in front) and returns; the work goes to the companion on the main actor afterwards, in a task that nothing waits for. Services
// give nothing back to the source app (no return types in the Info.plist): Replace is the user's own paste, after the result is on the pasteboard. The selected
// text is data and is never logged.

final class CompanionServicesProvider: NSObject {
    @objc func companionFix(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        start("fix", pboard, error: error)
    }

    @objc func companionRewrite(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        start("rewrite", pboard, error: error)
    }

    @objc func companionExplain(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        start("explain", pboard, error: error)
    }

    /// The text and the front app are read now (the service pasteboard is the OS's, valid for this call); the task starts the quick action and returns at once.
    /// Nothing selected (no text, or only blanks) sets the OS's error out-parameter, which the OS shows, and starts nothing.
    private func start(_ kind: String, _ pboard: NSPasteboard, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let text = pboard.string(forType: .string)
        guard let text, text.contains(where: { !$0.isWhitespace }) else {
            error.pointee = CompanionQuickRules.noSelectionNote as NSString
            return
        }
        let source = NSWorkspace.shared.frontmostApplication?.processIdentifier
        Task { @MainActor in
            Companion.shared.quick(kind: kind, text: text, sourcePID: source)
        }
    }
}
