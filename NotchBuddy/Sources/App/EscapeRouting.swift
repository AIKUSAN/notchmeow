import AppKit

/// Who gets ⎋ before the island closes.
enum EscapeRouting {
    /// The responder in `window`'s chain that handles ⎋ (`cancelOperation:`): a focused view with `.onExitCommand`
    /// (the "Other…" field, a list that goes back, a diff). Nil when none does, and then ⎋ closes the island.
    ///
    /// `NSApp.sendAction(_:to:from:)` cannot answer this: the panel itself responds to `cancelOperation:`, so it
    /// reports "handled" even when no view did, and the island would never close.
    @MainActor static func consumer(in window: NSWindow) -> NSResponder? {
        let cancel = #selector(NSStandardKeyBindingResponding.cancelOperation(_:))
        var responder = window.firstResponder
        while let current = responder, current !== window {
            if current.responds(to: cancel) { return current }
            responder = current.nextResponder
        }
        return nil
    }

    /// True while the focused text field is composing: an input method or a dead key has marked text on screen. ⎋
    /// then belongs to that composition (it cancels it), not to the island.
    @MainActor static func isComposing(in window: NSWindow) -> Bool {
        (window.firstResponder as? NSTextInputClient)?.hasMarkedText() ?? false
    }

    /// ⎋ closes the island only while it is open, unpinned and no request or question waits for an answer.
    static func shouldCollapse(expanded: Bool, pinned: Bool, decisionWaiting: Bool) -> Bool { expanded && !pinned && !decisionWaiting }
}
