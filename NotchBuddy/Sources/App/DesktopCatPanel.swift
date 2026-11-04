import AppKit

// The desktop cat's window (sub-project H): a borderless, non-activating floating panel that is never key, so it never steals focus. It joins every Space, stays out of fullscreen Spaces
// (no `.fullScreenAuxiliary`: it steps aside over a fullscreen app) and out of the window cycle. Clicks pass through everywhere except the cat's body: the controller flips
// `ignoresMouseEvents` from the mouse position (`DesktopCatLayout.hits`), so the panel takes the mouse only while it is over the body. The marker string below is in every build
// (Debug, Release and App Store), and scripts/check-app-binary.sh proves it.

final class DesktopCatPanel: NSPanel {
    /// In every build's binary: `check-app-binary.sh` looks for it. It is longer than 15 bytes on purpose: Swift keeps a shorter string inside the code, where `strings` cannot see it.
    static let marker = "NM_DESKTOP_CAT_PANEL"

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        identifier = NSUserInterfaceItemIdentifier(Self.marker)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating                                         // above windows, below the island and the menus
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]   // every Space, not fullscreen ones, not in the window cycle
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true                                 // click-through until the mouse is over the body
        acceptsMouseMovedEvents = true                            // the local mouse-moved monitor only sees moves over a window that accepts them
        isMovableByWindowBackground = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// The cat's window may rise above the screen's top edge at the notch spot, and macOS must not push it down (as the island's panel does).
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }
}

/// The cat's view: flipped (y down, like the contract and every canvas), it draws what the controller says and hands the mouse to it.
final class DesktopCatView: NSView {
    weak var controller: DesktopCatController?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        MainActor.assumeIsolated { controller?.draw(cg, dpr: Double(window?.backingScaleFactor ?? 2)) }
    }

    override func mouseDown(with event: NSEvent) { MainActor.assumeIsolated { controller?.mouseDown(event) } }
    override func mouseDragged(with event: NSEvent) { MainActor.assumeIsolated { controller?.mouseDragged(event) } }
    override func mouseUp(with event: NSEvent) { MainActor.assumeIsolated { controller?.mouseUp(event) } }
    override func rightMouseDown(with event: NSEvent) { MainActor.assumeIsolated { controller?.showMenu(with: event, in: self) } }
}
