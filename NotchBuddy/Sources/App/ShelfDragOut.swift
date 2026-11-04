import AppKit
import SwiftUI

// Dragging files out of the shelf (sub-project G1): a tile is also an AppKit view that turns a press that moves into a drag session, so the files can be dropped anywhere (Finder, Mail, a chat,
// a terminal). The session's source is `ShelfDragSource`: while it runs the island stays open and the panel keeps taking the mouse (`AppState.shelfHoldsIsland`, set by the hooks the view is
// given), and the drop view refuses a drag that started inside the app, so a file dragged out and back in is not added twice. Each file is opened (`ShelfStore.open`) for the length of the
// session, so a security-scoped original stays readable until the drop has finished.

/// What the app does when a drag out begins and ends (the render script and the tests give none).
struct ShelfDragHooks {
    var began: @MainActor () -> Void
    var ended: @MainActor () -> Void
    @MainActor static let none = ShelfDragHooks(began: {}, ended: {})
}

/// The drag session's source. It lets the files be copied by anything outside the app and refuses a drop inside it. It keeps itself alive until its session ends, so the files are closed and the
/// hold on the island is released even when the tile that started the drag has been redrawn or removed meanwhile.
@MainActor
final class ShelfDragSource: NSObject, NSDraggingSource {
    private var accesses: [ShelfAccess]
    private let onEnd: @MainActor () -> Void
    private var keptAlive: ShelfDragSource?

    init(accesses: [ShelfAccess], onEnd: @escaping @MainActor () -> Void) {
        self.accesses = accesses
        self.onEnd = onEnd
        super.init()
        keptAlive = self
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        for a in accesses { a.end() }
        accesses = []
        onEnd()
        keptAlive = nil
    }
}

/// A tile's mouse: a click selects it, a press that moves 4 pt drags the item out, or the whole selection when the tile is part of it.
@MainActor
final class ShelfTileNSView: NSView {
    var model: ShelfModel?
    var item: ShelfItem?
    var hooks = ShelfDragHooks.none
    private var pressed: NSEvent?
    private var dragging = false

    /// The island is a panel that never activates: the first press must count.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        pressed = event
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragging, let start = pressed, hypot(event.locationInWindow.x - start.locationInWindow.x, event.locationInWindow.y - start.locationInWindow.y) > 4 else { return }
        dragging = true
        // No session started (the file is gone): this press is not a drag, and the model has been told (`ShelfModel.open`), so the tile shows Missing.
        if !beginDrag(with: event) { dragging = false; pressed = nil }
    }

    override func mouseUp(with event: NSEvent) {
        if !dragging, let id = item?.id { model?.toggle(id) }
        pressed = nil
        dragging = false
    }

    // MARK: Accessibility: the overlay is the tile for VoiceOver (the SwiftUI tile under it is hidden)

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? {
        guard let item else { return nil }
        return "\(item.name), \(ShelfTile.detail(item, missing: model?.missing.contains(item.id) == true))"
    }
    override func isAccessibilitySelected() -> Bool { item.map { model?.selection.contains($0.id) == true } ?? false }
    override func accessibilityPerformPress() -> Bool {
        guard let id = item?.id else { return false }
        model?.toggle(id)
        return true
    }

    /// Whether a drag session began.
    private func beginDrag(with event: NSEvent) -> Bool {
        guard let model, let item else { return false }
        let chosen = model.selection.contains(item.id) ? model.selected : [item]
        let accesses = chosen.compactMap { model.open($0) }   // a missing file is skipped
        guard !accesses.isEmpty else { return false }
        // The end is the hooks' as they were when the drag began, not this view's: the view may be gone by then.
        let ended = hooks.ended
        let src = ShelfDragSource(accesses: accesses, onEnd: ended)
        let p = convert(event.locationInWindow, from: nil)
        let dragItems = accesses.enumerated().map { i, a -> NSDraggingItem in
            let di = NSDraggingItem(pasteboardWriter: a.url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: a.url.path)
            icon.size = NSSize(width: 40, height: 40)
            di.setDraggingFrame(NSRect(x: p.x - 20 + CGFloat(i) * 6, y: p.y - 20 - CGFloat(i) * 6, width: 40, height: 40), contents: icon)
            return di
        }
        hooks.began()
        let session = beginDraggingSession(with: dragItems, event: event, source: src)
        session.animatesToStartingPositionsOnCancelOrFail = true
        return true
    }
}

struct ShelfTileMouse: NSViewRepresentable {
    let model: ShelfModel
    let item: ShelfItem
    let hooks: ShelfDragHooks

    func makeNSView(context: Context) -> ShelfTileNSView {
        let v = ShelfTileNSView()
        configure(v)
        return v
    }

    func updateNSView(_ v: ShelfTileNSView, context: Context) { configure(v) }

    private func configure(_ v: ShelfTileNSView) {
        v.model = model
        v.item = item
        v.hooks = hooks
    }
}
