import Combine
import Foundation

#if DEBUG && !APPSTORE

/// The Debug-only shelf panel's model (sub-project G1): a shelf on a store in a temp folder, with buttons that fill it with real files, so the shelf view, the full-shelf note, a missing file and
/// the drop halves can be looked at and tried without touching the app's own shelf. Compiled in Debug builds only: `scripts/check-app-binary.sh` proves it is not in Release or App Store builds
/// (`marker`).
@MainActor
final class ShelfDevModel: ObservableObject {
    static let marker = "NM_SHELF_DEV_PANEL"

    let shelf: ShelfModel
    let root: URL
    /// True when the panel made its own folder: it is removed with the model. A folder the caller gave is the caller's.
    private let ownsRoot: Bool
    /// The half the drop layer shows as lit.
    @Published var half: DropHalf = .shelf
    /// What the panel's buttons did, newest last. The Ask, Send and AirDrop buttons only say here what they would do: the real ones need the island.
    @Published private(set) var log: [String] = []
    private var counter = 0

    init(root given: URL? = nil) {
        let root = given ?? FileManager.default.temporaryDirectory.appendingPathComponent("NotchMeow-shelf-dev-\(UUID().uuidString)", isDirectory: true)
        self.root = root
        ownsRoot = given == nil
        try? FileManager.default.createDirectory(at: root.appendingPathComponent("originals"), withIntermediateDirectories: true)
        shelf = ShelfModel(store: ShelfStore(support: root.appendingPathComponent("support"), scoped: false))
    }

    deinit {
        if ownsRoot { try? FileManager.default.removeItem(at: root) }
    }

    func say(_ line: String) { log.append(line); if log.count > 8 { log.removeFirst(log.count - 8) } }

    /// A real file of `bytes` zeros in a folder of its own, so the same name can be made twice.
    private func make(_ name: String, bytes: Int) -> URL {
        counter += 1
        let dir = root.appendingPathComponent("originals/\(counter)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try? Data(count: bytes).write(to: url)
        return url
    }

    func addSamples() {
        let r = shelf.add([.file(make("Quarterly report.pdf", bytes: 2_400_000)), .file(make("notes.txt", bytes: 1_200)), .file(make("demo.mov", bytes: 4_800))])
        say("dropped 3 files: \(r.map(\.rawValue).joined(separator: ", "))")
    }

    func addImageCopy() {
        let r = shelf.add([.temporary(make("Image.png", bytes: 48_000))])
        say("dropped an image with no original (a copy): \(r.map(\.rawValue).joined(separator: ", "))")
    }

    /// Fills the shelf to its 30.
    func fill() {
        let room = max(0, ShelfRules.max - shelf.count)
        let r = shelf.add((0..<room).map { .file(make("file-\(counter + $0).txt", bytes: 1_000)) })
        say("filled the shelf: \(r.count) added")
    }

    /// Two more files on a full shelf: both are refused and nothing old is removed.
    func dropTwoMore() {
        let r = shelf.add([.file(make("extra-a.txt", bytes: 10)), .file(make("extra-b.txt", bytes: 10))])
        say("dropped 2 more: \(r.map(\.rawValue).joined(separator: ", "))")
    }

    /// Deletes the original of the newest linked item, so it shows as missing.
    func deleteAnOriginal() {
        guard let item = shelf.items.first(where: { !$0.copy }), let access = shelf.open(item) else { say("no link to delete"); return }
        let url = access.url
        access.end()
        try? FileManager.default.removeItem(at: url)
        shelf.refresh()
        say("deleted the original of \(item.name): it is missing now")
    }

    func clear() {
        shelf.clear()
        say("cleared the shelf")
    }
}

#endif
