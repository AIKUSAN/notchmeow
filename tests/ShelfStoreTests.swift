import Foundation

// The shelf's storage against real files in a temp folder: bookmarks, copies, the cap, a file that went missing, the backup of an unreadable shelf.json, and that originals are never
// touched. Run it through scripts/test-shelf-store.sh.

@main
enum ShelfStoreTests {
    static var fm: FileManager { .default }

    static func temp(_ name: String) -> URL {
        let base = URL(fileURLWithPath: ProcessInfo.processInfo.environment["NM_LOG_DIR"]!).deletingLastPathComponent()
        let dir = base.appendingPathComponent(name, isDirectory: true)
        try? fm.removeItem(at: dir)
        try! fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func write(_ dir: URL, _ name: String, _ text: String = "hello") -> URL {
        let u = dir.appendingPathComponent(name)
        try! text.write(to: u, atomically: true, encoding: .utf8)
        return u
    }

    /// A store with a counter for ids and a clock that moves one second at a time, so the order is known.
    static func makeStore(_ support: URL) -> ShelfStore {
        nonisolated(unsafe) var n = 0
        nonisolated(unsafe) var t: Int64 = 1_000
        return ShelfStore(support: support, scoped: false, now: { t += 1000; return t }, newID: { n += 1; return "id\(n)" })
    }

    @MainActor static func main() {
        CT.section("adding originals: links, no copies")
        let work = temp("shelf-store-work")
        let originals = work.appendingPathComponent("originals", isDirectory: true)
        try! fm.createDirectory(at: originals, withIntermediateDirectories: true)
        let support = work.appendingPathComponent("support", isDirectory: true)
        let store = makeStore(support)
        store.load()
        CT.check("a new shelf is empty and writes nothing yet", [store.items.count, fm.fileExists(atPath: store.file.path) ? 1 : 0], [0, 0])
        let a = write(originals, "a.txt", "alpha")
        let folder = originals.appendingPathComponent("A Folder", isDirectory: true)
        try! fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let r = store.add([.file(a), .file(folder)])
        CT.check("a file and a folder are added", r, [.added, .added])
        CT.check("newest first: the folder was made after the file, so it comes first", store.items.map(\.name), ["A Folder", "a.txt"])
        let byName = Dictionary(uniqueKeysWithValues: store.items.map { ($0.name, $0) })
        CT.check("the file is a link of 5 bytes, not a copy", [byName["a.txt"]!.copy, byName["a.txt"]!.folder, byName["a.txt"]!.size == 5, byName["a.txt"]!.link != nil], [false, false, true, true])
        CT.check("the folder is a link too, marked as a folder", [byName["A Folder"]!.copy, byName["A Folder"]!.folder], [false, true])
        CT.checkTrue("nothing was copied into shelf/", !fm.fileExists(atPath: store.copiesRoot.path))
        CT.checkTrue("shelf.json was written and reads back as the same items", ShelfRules.read([UInt8](try! Data(contentsOf: store.file))) == store.items)

        CT.section("the same file twice is one item")
        CT.check("dropping a.txt again is a duplicate, though its bookmark would not be the same bytes", store.add([.file(a)]), [.duplicate])
        CT.check("the same file twice in one drop: the second is a duplicate", store.add([.file(write(originals, "b.txt")), .file(originals.appendingPathComponent("b.txt"))]), [.added, .duplicate])
        CT.check("three items now", store.items.count, 3)

        CT.section("a file with no original is copied")
        let tmp = temp("shelf-store-tmp")
        let img = write(tmp, "Image.png", "png!")
        CT.check("a temporary file is added as a copy", store.add([.temporary(img)]), [.added])
        let copy = store.items.first { $0.copy }!
        CT.check("it has no link, and its file is shelf/<id>/<name> with the same bytes", [copy.link == nil, (try? String(contentsOf: store.copyURL(copy), encoding: .utf8)) == "png!"], [true, true])
        CT.checkTrue("the caller's own file is still there", fm.fileExists(atPath: img.path))
        CT.check("a name the contract refuses is invalid and leaves no folder behind", store.add([.temporary(write(tmp, "CON.txt"))]), [.invalid])
        CT.check("only the one copy folder exists", (try? fm.contentsOfDirectory(atPath: store.copiesRoot.path))?.sorted() ?? [], [copy.id])
        CT.check("a file that does not exist is invalid", store.add([.file(originals.appendingPathComponent("nope.txt"))]), [.invalid])

        CT.section("using an item")
        let opened = store.open(byName["a.txt"]!)
        CT.check("a link opens to its original", opened?.url.standardizedFileURL.path, a.standardizedFileURL.path)
        opened?.end()
        CT.check("a copy opens to its copy", store.open(copy)?.url.lastPathComponent, "Image.png")
        CT.check("nothing is missing yet", store.checkMissing(), [])

        CT.section("a moved or deleted original is missing, never touched")
        try! fm.removeItem(at: a)
        CT.check("the deleted file is missing; the others are not", store.checkMissing(), [byName["a.txt"]!.id])
        CT.checkTrue("and opening it gives nothing", store.open(byName["a.txt"]!) == nil)
        let c = write(originals, "c.txt", "keep me")
        store.add([.file(c)])
        let cItem = store.items.first { $0.name == "c.txt" }!
        store.remove(id: cItem.id)
        CT.checkTrue("removing a link leaves its original alone", fm.fileExists(atPath: c.path))
        store.remove(id: copy.id)
        CT.checkTrue("removing a copy deletes its folder", !fm.fileExists(atPath: store.folder(for: copy.id).path))
        CT.check("removing something that is not there changes nothing", { let n = store.items.count; store.remove(id: "nope"); return store.items.count == n }(), true)

        CT.section("a restart")
        let again = makeStore(support)
        again.load()
        CT.check("a new store on the same folder sees the same shelf", again.items, store.items)

        CT.section("the cap: 30, and a full shelf refuses")
        let cap = makeStore(temp("shelf-store-cap"))
        cap.load()
        var files: [ShelfIncoming] = []
        for n in 0..<32 { files.append(.file(write(originals, "n\(n).txt", "\(n)"))) }
        let rc = cap.add(files)
        CT.check("thirty are added and two are refused as full", [rc.filter { $0 == .added }.count, rc.filter { $0 == .full }.count], [30, 2])
        CT.check("30 on the shelf", cap.items.count, 30)
        let newFile = write(originals, "late.txt")
        CT.check("a later drop on the full shelf is refused and removes nothing", [cap.add([.file(newFile)]) == [.full], cap.items.count == 30], [true, true])
        CT.check("a copy refused as full is refused", cap.add([.temporary(write(tmp, "full.png"))]), [.full])
        CT.checkTrue("and leaves no folder behind", !fm.fileExists(atPath: cap.copiesRoot.path) || ((try? fm.contentsOfDirectory(atPath: cap.copiesRoot.path))?.isEmpty ?? true))
        cap.clear()
        CT.check("Clear all empties the shelf and the file", [cap.items.count, ShelfRules.read([UInt8](try! Data(contentsOf: cap.file))).count], [0, 0])

        CT.section("an unreadable shelf.json is kept before a new one is written")
        let badSupport = temp("shelf-store-bad")
        try! "{ this is not json".write(to: badSupport.appendingPathComponent("shelf.json"), atomically: true, encoding: .utf8)
        let bad = makeStore(badSupport)
        bad.load()
        CT.check("it reads as an empty shelf", bad.items.count, 0)
        CT.check("and loading wrote nothing", try! String(contentsOf: bad.file, encoding: .utf8), "{ this is not json")
        bad.add([.file(write(originals, "x.txt"))])
        let kept = (try? fm.contentsOfDirectory(atPath: badSupport.path))?.filter { $0.hasPrefix("shelf.json.bad-") } ?? []
        CT.check("the first write kept the old file as shelf.json.bad-<time>", kept.count, 1)
        CT.check("byte for byte", kept.first.flatMap { try? String(contentsOf: badSupport.appendingPathComponent($0), encoding: .utf8) }, "{ this is not json")
        bad.add([.file(write(originals, "y.txt"))])
        CT.check("a second write keeps no second copy", ((try? fm.contentsOfDirectory(atPath: badSupport.path))?.filter { $0.hasPrefix("shelf.json.bad-") } ?? []).count, 1)
        // A clean file is never backed up; a file with a hostile item in it is, because reading it drops the item.
        let cleanSupport = temp("shelf-store-clean")
        let clean = makeStore(cleanSupport)
        clean.load()
        clean.add([.file(write(originals, "p.txt"))])
        let clean2 = makeStore(cleanSupport)
        clean2.load()
        clean2.add([.file(write(originals, "q.txt"))])
        CT.check("a shelf the app wrote itself is never backed up", ((try? fm.contentsOfDirectory(atPath: cleanSupport.path))?.filter { $0.hasPrefix("shelf.json.bad-") } ?? []).count, 0)
        let lossySupport = temp("shelf-store-lossy")
        try! "{\"items\":[{\"id\":\"../x\",\"name\":\"f\",\"link\":\"/p\"}]}".write(to: lossySupport.appendingPathComponent("shelf.json"), atomically: true, encoding: .utf8)
        let lossy = makeStore(lossySupport)
        lossy.load()
        lossy.add([.file(write(originals, "r.txt"))])
        CT.check("a file with an item that reading drops is kept too", ((try? fm.contentsOfDirectory(atPath: lossySupport.path))?.filter { $0.hasPrefix("shelf.json.bad-") } ?? []).count, 1)

        CT.section("a shelf.json that cannot be read is never written over")
        let stuckSupport = temp("shelf-store-stuck")
        let stuckFile = stuckSupport.appendingPathComponent("shelf.json")
        try! "keep me".write(to: stuckFile, atomically: true, encoding: .utf8)
        try! fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: stuckFile.path)
        if (try? Data(contentsOf: stuckFile)) != nil {
            print("  - skipped: shelf.json stays readable with mode 000 here (running as root?), so the permission case cannot be made")
            try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: stuckFile.path)
        } else {
            let stuck = makeStore(stuckSupport)
            stuck.load()
            CT.check("an unreadable shelf.json reads as an empty shelf", stuck.items.count, 0)
            stuck.add([.file(write(originals, "z.txt"))])
            // A drop whose write is refused adds nothing: invalid, no item on screen, no copy left in shelf/.
            let refused = stuck.add([.temporary(write(originals, "refused.png")), .file(write(originals, "refused.txt"))])
            try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: stuckFile.path)
            CT.check("the write was refused, so the old bytes are still there", try? String(contentsOf: stuckFile, encoding: .utf8), "keep me")
            CT.check("no shelf.json.bad- copy was made either", ((try? fm.contentsOfDirectory(atPath: stuckSupport.path))?.filter { $0.hasPrefix("shelf.json.bad-") } ?? []).count, 0)
            CT.check("the failure is recorded in lastError", stuck.lastError != nil, true)
            CT.check("a refused write reports every file that would have been added as invalid", refused, [.invalid, .invalid])
            CT.check("and the list is unchanged", stuck.items.count, 0)
            CT.checkTrue("and no copy folder is left under shelf/", !fm.fileExists(atPath: stuck.copiesRoot.path) || ((try? fm.contentsOfDirectory(atPath: stuck.copiesRoot.path))?.isEmpty ?? true))
        }

        CT.section("a write that is refused after items were already on the shelf")
        let lockedSupport = temp("shelf-store-locked")
        let locked = makeStore(lockedSupport)
        locked.load()
        locked.add([.file(write(originals, "kept.txt"))])
        let before = locked.items
        try! fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: lockedSupport.path)
        if fm.createFile(atPath: lockedSupport.appendingPathComponent("probe").path, contents: nil) {
            print("  - skipped: a read-only folder stays writable here (running as root?), so the refused write cannot be made")
            try? fm.removeItem(at: lockedSupport.appendingPathComponent("probe"))
        } else {
            let r = locked.add([.temporary(write(originals, "late.png")), .file(write(originals, "late.txt"))])
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: lockedSupport.path)
            CT.check("both are invalid", r, [.invalid, .invalid])
            CT.check("the list is what it was", locked.items, before)
            CT.checkTrue("the copy made for the refused drop is removed", ((try? fm.contentsOfDirectory(atPath: locked.copiesRoot.path)) ?? []).isEmpty)
            CT.checkTrue("the failure is recorded in lastError", locked.lastError != nil)
            CT.check("and a later write, once the folder is writable, works", locked.add([.file(write(originals, "later.txt"))]), [.added])
        }

        CT.section("a package is a file, not a folder")
        let pkgSupport = temp("shelf-store-pkg")
        let pkgs = makeStore(pkgSupport)
        pkgs.load()
        let rtfd = originals.appendingPathComponent("Notes.rtfd", isDirectory: true)
        try! fm.createDirectory(at: rtfd, withIntermediateDirectories: true)
        _ = write(rtfd, "TXT.rtf", "{\\rtf1 hi}")
        let plain = originals.appendingPathComponent("Plain Folder", isDirectory: true)
        try! fm.createDirectory(at: plain, withIntermediateDirectories: true)
        CT.check("a package and a folder are added", pkgs.add([.file(rtfd), .file(plain)]), [.added, .added])
        CT.check("the package (a .rtfd, which macOS itself knows as one) is not a folder; the plain folder still is", pkgs.items.map { [$0.name, "\($0.folder)"] }, [["Plain Folder", "true"], ["Notes.rtfd", "false"]])

        CT.section("a bookmark is resolved without asking macOS to mount a volume")
        CT.checkTrue("an unmounted share is not reconnected: both builds resolve without UI and without mounting",
                     ShelfStore.resolveOptions(scoped: false).isSuperset(of: [.withoutUI, .withoutMounting]) && ShelfStore.resolveOptions(scoped: true).isSuperset(of: [.withSecurityScope, .withoutUI, .withoutMounting]))

        CT.section("an item is opened from the store's own copy of it")
        let own = makeStore(temp("shelf-store-own"))
        own.load()
        let ownFile = write(originals, "own.txt", "own")
        own.add([.file(ownFile)])
        var callers = own.items[0]
        callers.link = "bm9wZQ=="   // the caller holds an old or damaged copy of the item
        CT.check("the link the store holds opens it, not the caller's", own.open(callers)?.url.standardizedFileURL.path, ownFile.standardizedFileURL.path)

        CT.section("a promised file dropped twice is one item (name and bytes, not the temp path)")
        let promised = makeStore(temp("shelf-store-promised"))
        promised.load()
        func folders() -> [String] { ((try? fm.contentsOfDirectory(atPath: promised.copiesRoot.path)) ?? []).sorted() }
        let t1 = temp("shelf-promise-1"), t2 = temp("shelf-promise-2"), t3 = temp("shelf-promise-3")
        let first = write(t1, "Report.pdf", "same bytes")
        CT.check("the first is added", promised.add([.temporary(first)]), [.added])
        CT.check("the same file again, from another temp folder, is a duplicate", promised.add([.temporary(write(t2, "Report.pdf", "same bytes"))]), [.duplicate])
        CT.check("and no second folder was made", [folders().count, promised.items.count], [1, 1])
        CT.check("the same name with other bytes (same size) is a different file", promised.add([.temporary(write(t3, "Report.pdf", "other bytes"))]), [.added])
        CT.check("the same name with another size is a different file too", promised.add([.temporary(write(temp("shelf-promise-4"), "Report.pdf", "longer than the others"))]), [.added])
        CT.check("a renamed copy with the same bytes is let through", promised.add([.temporary(write(temp("shelf-promise-5"), "Report 2.pdf", "same bytes"))]), [.added])
        CT.check("four items, four folders", [promised.items.count, folders().count], [4, 4])
        let drop = temp("shelf-promise-6"), drop2 = temp("shelf-promise-7")
        CT.check("the same file twice in one drop: the second is a duplicate", promised.add([.temporary(write(drop, "Twice.txt", "tw")), .temporary(write(drop2, "Twice.txt", "tw"))]), [.added, .duplicate])
        CT.check("and the same file twice in one drop, one after the other, still one folder for it", promised.items.filter { $0.name == "Twice.txt" }.count, 1)
        CT.check("a new name in the same drop as a duplicate is added", promised.add([.temporary(write(drop, "Twice.txt", "tw")), .temporary(write(drop, "Thrice.txt", "th"))]), [.duplicate, .added])
        // A copy that is gone from disk is not a match; one that cannot be read does not stop the drop either.
        let gone = promised.items.first { $0.name == "Report.pdf" && $0.size == 10 }!
        try! fm.removeItem(at: promised.copyURL(gone))
        CT.check("a copy that is missing on disk is not a match: the file is added again", promised.add([.temporary(write(temp("shelf-promise-8"), "Report.pdf", "same bytes"))]), [.added])
        let unreadable = promised.items.first { $0.name == "Twice.txt" }!
        try! fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: promised.copyURL(unreadable).path)
        if (try? Data(contentsOf: promised.copyURL(unreadable))) != nil {
            print("  - skipped: the copy stays readable with mode 000 here (running as root?), so the unreadable case cannot be made")
        } else {
            CT.check("a compare that cannot read the copy falls through to add", promised.add([.temporary(write(temp("shelf-promise-9"), "Twice.txt", "tw"))]), [.added])
        }
        try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: promised.copyURL(unreadable).path)

        CT.finish()
    }
}
