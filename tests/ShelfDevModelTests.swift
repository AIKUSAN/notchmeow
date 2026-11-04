import Foundation

#if DEBUG && !APPSTORE

// The Debug-only shelf panel's model: its buttons fill a shelf of its own (in a temp folder) with real files. Run it through scripts/test-shelf-devpanel.sh.

@main
enum ShelfDevModelTests {
    @MainActor static func main() {
        CT.section("the panel's own shelf")
        let tmp = URL(fileURLWithPath: ProcessInfo.processInfo.environment["NM_LOG_DIR"]!).deletingLastPathComponent().appendingPathComponent("shelf-dev", isDirectory: true)
        let dev = ShelfDevModel(root: tmp)
        CT.check("it starts empty, on a store inside the folder it was given", [dev.shelf.count, dev.shelf.store.support.path.hasPrefix(tmp.path) ? 1 : 0], [0, 1])
        dev.addSamples()
        CT.check("three files are added as links", [dev.shelf.count, dev.shelf.items.filter { !$0.copy }.count], [3, 3])
        dev.addImageCopy()
        CT.check("an image with no original is a copy", dev.shelf.items.filter { $0.copy }.count, 1)
        dev.fill()
        CT.check("fill brings the shelf to 30", dev.shelf.count, 30)
        dev.dropTwoMore()
        CT.check("two more on a full shelf are refused, and nothing is removed", [dev.shelf.count, dev.shelf.note?.contains("30 at most: 2 files were not added") == true ? 1 : 0], [30, 1])
        dev.deleteAnOriginal()
        CT.check("deleting an original makes exactly one item missing", dev.shelf.missing.count, 1)
        dev.clear()
        CT.check("clear empties the shelf", dev.shelf.count, 0)
        CT.check("the log keeps the last eight lines", dev.log.count <= 8 && !dev.log.isEmpty, true)
        CT.check("the marker is the one check-app-binary.sh looks for", ShelfDevModel.marker, "NM_SHELF_DEV_PANEL")

        CT.section("the panel's samples are small and its temp folder goes with it")
        var small: ShelfDevModel? = ShelfDevModel()
        let smallRoot = small!.root
        small!.addSamples()
        CT.check("the sample 'movie' is a few KB, not 48 MB", small!.shelf.items.filter { $0.name == "demo.mov" }.map { $0.size < 10_000 }, [true])
        CT.checkTrue("the folder of a panel that was given none is there while the panel is", FileManager.default.fileExists(atPath: smallRoot.path))
        small = nil
        CT.checkTrue("and is removed when the panel's model is released", !FileManager.default.fileExists(atPath: smallRoot.path))
        CT.checkTrue("a folder the caller gave is the caller's: it stays", { let d = ShelfDevModel(root: tmp); _ = d; return FileManager.default.fileExists(atPath: tmp.path) }())

        CT.section("the model: an empty drop says so, a failed open turns the tile Missing, a refresh re-syncs")
        let mroot = tmp.appendingPathComponent("model", isDirectory: true)
        try? FileManager.default.createDirectory(at: mroot, withIntermediateDirectories: true)
        let model = ShelfModel(store: ShelfStore(support: mroot.appendingPathComponent("support"), scoped: false))
        CT.check("a drop with nothing in it adds nothing", [model.add([]).count, model.count], [0, 0])
        CT.check("the note says nothing could be added", model.note, "Nothing could be added.")
        let file = mroot.appendingPathComponent("a.txt")
        try! "a".write(to: file, atomically: true, encoding: .utf8)
        model.add([.file(file)])
        CT.check("a later drop that adds something clears it", model.note == nil, true)
        let item = model.items[0]
        let there = model.open(item)
        there?.end()
        CT.checkTrue("an item that is there opens", there != nil)
        CT.check("and is not missing", model.missing.isEmpty, true)
        try! FileManager.default.removeItem(at: file)
        CT.checkTrue("an item whose file is gone does not open", model.open(item) == nil)
        CT.check("and the failed open turned it Missing, with no one asking the shelf to refresh", model.missing, [item.id])
        model.store.remove(id: item.id)
        model.refresh()
        CT.check("a refresh takes the store's list as it is now", [model.items.count, model.missing.count], [0, 0])
        CT.finish()
    }
}

#else

@main
enum ShelfDevModelTests {
    static func main() { print("build with -D DEBUG"); exit(2) }
}

#endif
