import Foundation

// What a drop on the Shelf half does to the rest of the app (sub-project G1), in one place.

@MainActor
enum ShelfFlow {
    /// At the moment files are dropped on the Shelf half (before any promised file has arrived): the drop takes a fresh token (so the delayed work of an Ask drop that was still running no longer touches the state), the file-drag alert ends (the
    /// desktop cat, if it was flying in to catch the file, goes back by its normal rule), the drop view's half is cleared and the upload sequence stops. There is no wait for the desktop cat and no
    /// catch: a Shelf drop never goes through the Ask drop's handler.
    static func afterShelfDrop(state: AppState) {
        _ = FileDropHandler.drops.begin()
        state.fileDragOver = false
        state.dropHalf = nil
        UploadSequenceEngine.shared.deactivate()
    }
}
