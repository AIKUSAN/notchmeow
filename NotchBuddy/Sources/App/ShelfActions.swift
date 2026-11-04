import AppKit

// What the shelf's buttons do (sub-project G1). Each opens the item first (`ShelfStore.open`: a security-scoped original is readable only while it is open).

@MainActor
enum ShelfActions {
    /// The file Ask is reading stays open until the next Ask: the chat reads and copies it after this returns.
    private static var held: ShelfAccess?

    /// Ask: hands the file to the chat the way a drop on the Ask half does. The upload sequence starts and the island shows its canvas, then `FileDropHandler.handle` runs the drop as it always has:
    /// the desktop cat catches the file if it is out, the cat catches it at the notch, the conversation resets and the file is the chat's context.
    static func ask(_ item: ShelfItem, model: ShelfModel, state: AppState = .shared) {
        guard ShelfActionRules.canAsk([item], missing: model.missing), let access = model.open(item) else { return }
        held?.end()
        held = access
        state.fileDragOver = true
        UploadSequenceEngine.shared.enterZone(x: 320, y: 110)
        NotificationCenter.default.post(name: .hookExpand, object: IslandView.upload)
        Task { @MainActor in await FileDropHandler.handle(urls: [access.url], state: state) }
    }

    /// Send (the share picker) and AirDrop: see `ShelfSend`.
    static func send(_ items: [ShelfItem], model: ShelfModel) { ShelfSend.shared.showPicker(items, model: model) }
    static func airDrop(_ items: [ShelfItem], model: ShelfModel) { ShelfSend.shared.airDrop(items, model: model) }

    /// Show in Finder (the system's file viewer, with the items selected). Never touches the files.
    static func showInFinder(_ items: [ShelfItem], model: ShelfModel) {
        let accesses = items.compactMap { model.open($0) }
        guard !accesses.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(accesses.map(\.url))
        for a in accesses { a.end() }
    }
}
