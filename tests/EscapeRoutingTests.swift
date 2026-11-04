import AppKit
import SwiftUI

/// ⎋ in the island: which responder, if any, takes it before the island closes. Real SwiftUI views in an invisible
/// panel (alpha 0, no mouse), like the island's own, so it needs a logged-in macOS session.
@main
enum EscapeRoutingTests {
    nonisolated(unsafe) static var cases = 0
    nonisolated(unsafe) static var exitHits = 0

    static func check(_ ok: Bool, _ message: @autoclosure () -> String,
                      file: StaticString = #file, line: UInt = #line) {
        cases += 1
        precondition(ok, message(), file: file, line: line)
    }

    final class KeyPanel: NSPanel { override var canBecomeKey: Bool { true } }

    enum Kind { case nothingFocused, button, textField, focusedViewWithExit, textFieldWithExit }

    struct Content: View {
        let kind: Kind
        @FocusState private var focused: Bool
        @State private var text = ""
        var body: some View {
            switch kind {
            case .nothingFocused:
                Text("card").frame(width: 120, height: 40)
            case .button:
                Button("go") {}.frame(width: 120, height: 40)
            case .textField:
                TextField("Ask me anything…", text: $text).focused($focused)
                    .onAppear { focused = true }.frame(width: 120, height: 40)
            case .focusedViewWithExit:
                Text("list").frame(width: 120, height: 40).focusable().focused($focused)
                    .onAppear { focused = true }.onExitCommand { EscapeRoutingTests.exitHits += 1 }
            case .textFieldWithExit:
                TextField("Other…", text: $text).focused($focused)
                    .onAppear { focused = true }.onExitCommand { EscapeRoutingTests.exitHits += 1 }
                    .frame(width: 120, height: 40)
            }
        }
    }

    /// Shows `kind` in a key panel, lets SwiftUI settle, and runs `body` with the panel.
    @MainActor static func inPanel(_ kind: Kind, _ body: (NSPanel) -> Void) {
        let panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 120, height: 40),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: Content(kind: kind))
        panel.orderFrontRegardless()
        panel.makeKey()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        body(panel)
        panel.orderOut(nil)
    }

    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let cancel = #selector(NSStandardKeyBindingResponding.cancelOperation(_:))

        // The reason this type exists: the panel always answers cancelOperation:, so sendAction says "handled".
        inPanel(.nothingFocused) { panel in
            check(panel.isKeyWindow, "the panel is the key window")
            check(NSApp.sendAction(cancel, to: nil, from: nil), "sendAction says handled even though no view did")
            check(EscapeRouting.consumer(in: panel) == nil, "but no view in the chain handles it")
        }
        inPanel(.button) { panel in
            check(EscapeRouting.consumer(in: panel) == nil, "a button does not take ⎋")
        }
        inPanel(.textField) { panel in
            check(panel.firstResponder != nil && panel.firstResponder !== panel, "the chat field has the focus")
            check(EscapeRouting.consumer(in: panel) == nil, "a text field without .onExitCommand does not take ⎋: the island closes")
            // An input method or a dead key composing in the field: ⎋ cancels the composition, the island stays.
            check(!EscapeRouting.isComposing(in: panel), "nothing is composing yet")
            guard let input = panel.firstResponder as? NSTextInputClient else {
                preconditionFailure("the field's editor must be a text input client")
            }
            input.setMarkedText("é", selectedRange: NSRange(location: 1, length: 0),
                                replacementRange: NSRange(location: NSNotFound, length: 0))
            check(EscapeRouting.isComposing(in: panel), "marked text means the field is composing")
            input.unmarkText()
            check(!EscapeRouting.isComposing(in: panel), "and not any more once it is committed")
        }
        inPanel(.nothingFocused) { panel in
            check(!EscapeRouting.isComposing(in: panel), "no text field, no composition")
        }
        inPanel(.focusedViewWithExit) { panel in
            exitHits = 0
            guard let responder = EscapeRouting.consumer(in: panel) else {
                preconditionFailure("a focused view with .onExitCommand must take ⎋")
            }
            check(NSApp.sendAction(cancel, to: responder, from: nil), "the action is delivered")
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            check(exitHits == 1, "and its .onExitCommand ran once (\(exitHits))")
        }
        inPanel(.textFieldWithExit) { panel in
            exitHits = 0
            guard let responder = EscapeRouting.consumer(in: panel) else {
                preconditionFailure("the Other… field's .onExitCommand must take ⎋")
            }
            _ = NSApp.sendAction(cancel, to: responder, from: nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            check(exitHits == 1, "the field's .onExitCommand ran once (\(exitHits))")
        }
        for expanded in [false, true] {
            for pinned in [false, true] {
                for waiting in [false, true] {
                    let want = expanded && !pinned && !waiting
                    let name = expanded && !pinned && waiting
                        ? "waiting question: global ⎋ must not close"
                        : "shouldCollapse(expanded: \(expanded), pinned: \(pinned), waiting: \(waiting)) is \(want)"
                    check(EscapeRouting.shouldCollapse(expanded: expanded, pinned: pinned, decisionWaiting: waiting) == want, name)
                }
            }
        }
        print("Escape routing: \(cases) cases passed")
    }
}
