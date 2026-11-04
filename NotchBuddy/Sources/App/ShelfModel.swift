import Combine
import Foundation

// What the shelf view shows and the actions on it (sub-project G1): the store's items, which of them are selected, which have gone missing, and the note after a drop. Foundation and Combine
// only, so the render script and the tests can build one on a store in a temp folder; the app's own is `ShelfModel.shared` (ShelfModel+App.swift).

@MainActor
final class ShelfModel: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []
    /// Items whose file is gone. Asked when the shelf opens (`refresh`), never in the background.
    @Published private(set) var missing: Set<String> = []
    @Published private(set) var selection: Set<String> = []
    /// What to tell the user after a drop that did not add everything; cleared by the next change.
    @Published private(set) var note: String?
    let store: ShelfStore

    init(store: ShelfStore) {
        self.store = store
        store.load()
        items = store.items
    }

    var count: Int { items.count }
    /// The selected items, in the shelf's order.
    var selected: [ShelfItem] { items.filter { selection.contains($0.id) } }

    private func sync() {
        items = store.items
        let ids = Set(items.map(\.id))
        selection.formIntersection(ids)
        missing.formIntersection(ids)
    }

    /// Files dropped on the Shelf half. Returns one word for each, and sets the note.
    @discardableResult
    func add(_ incoming: [ShelfIncoming]) -> [ShelfAddResult] {
        let results = store.add(incoming)
        sync()
        // A drop of nothing (nothing decodable, a promise that failed) has no results for `ShelfDrop.note` to word, and the shelf opens all the same: say so.
        note = incoming.isEmpty ? "Nothing could be added." : ShelfDrop.note(results)
        return results
    }

    /// The shelf opened: ask which files are still there.
    func refresh() {
        missing = store.checkMissing()
        sync()   // the check may have renewed a stale bookmark in the store's items
    }

    func toggle(_ id: String) {
        guard items.contains(where: { $0.id == id }) else { return }
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        note = nil
    }

    func remove(_ ids: Set<String>) {
        for id in ids { store.remove(id: id) }
        sync()
        note = nil
    }

    func clear() {
        store.clear()
        sync()
        selection = []
        missing = []
        note = nil
    }

    func dismissNote() { note = nil }

    /// A file that cannot be opened is gone: ask again which are, so its tile turns Missing instead of the action doing nothing.
    func open(_ item: ShelfItem) -> ShelfAccess? {
        let access = store.open(item)
        if access == nil { refresh() }
        return access
    }
}
