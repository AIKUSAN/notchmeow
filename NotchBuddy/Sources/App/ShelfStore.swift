import Foundation

// The shelf's storage (sub-project G1): `shelf.json` (the list, read and written through ShelfRules), a security-scoped bookmark per item, and a copy under `shelf/<id>/<name>` only for a
// file that has no original (a promised file, a browser image). Originals are never touched. Foundation only; the App Store build asks for scoped bookmarks, the GitHub build is not
// sandboxed and uses plain ones through the same code. Nothing here runs in the background: whether a file still exists is asked when the shelf opens (`checkMissing`).

/// What a drop hands the store for each file.
enum ShelfIncoming {
    /// An original on disk: kept as a link (a folder too).
    case file(URL)
    /// A file with no original (a promised file, a browser image): copied into `shelf/<id>/`. The caller may delete its own copy afterwards.
    case temporary(URL)
}

/// A shelf item opened for use: its file, and the security scope that keeps it readable until `end()`.
final class ShelfAccess {
    let url: URL
    private var scoped: Bool
    init(url: URL, scoped: Bool) { self.url = url; self.scoped = scoped }
    func end() {
        guard scoped else { return }
        scoped = false
        url.stopAccessingSecurityScopedResource()
    }
    deinit { if scoped { url.stopAccessingSecurityScopedResource() } }
}

final class ShelfStore {
    /// The shelf is in every build (GitHub, Release and App Store); `scripts/check-app-binary.sh` looks for this string in all three. The shelf view carries it as its accessibility identifier.
    static let marker = "NM_SHELF_STORE_ACTIVE"

    #if APPSTORE
    static let isAppStoreBuild = true
    #else
    static let isAppStoreBuild = false
    #endif

    let support: URL
    private(set) var items: [ShelfItem] = []
    /// Why the last write failed, for the log; nil when it worked.
    private(set) var lastError: String?
    private let scoped: Bool
    private let now: () -> Int64
    private let newID: () -> String
    /// Set by `load` when shelf.json holds something reading it would lose: the first write keeps a copy of the old file.
    private var backupFirst = false

    init(support: URL, scoped: Bool = ShelfStore.isAppStoreBuild,
         now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
         newID: @escaping () -> String = { UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() }) {
        self.support = support
        self.scoped = scoped
        self.now = now
        self.newID = newID
    }

    var file: URL { support.appendingPathComponent("shelf.json") }
    var copiesRoot: URL { support.appendingPathComponent("shelf") }
    func folder(for id: String) -> URL { copiesRoot.appendingPathComponent(id, isDirectory: true) }
    func copyURL(_ item: ShelfItem) -> URL { folder(for: item.id).appendingPathComponent(item.name) }

    // MARK: Reading and writing the list

    func load() {
        // A file that exists but cannot be read is kept by the first write, the same as one that reads badly (a missing file is not).
        guard let data = try? Data(contentsOf: file) else { items = []; backupFirst = FileManager.default.fileExists(atPath: file.path); return }
        let bytes = [UInt8](data)
        items = ShelfRules.read(bytes)
        backupFirst = !bytes.isEmpty && !ShelfRules.isLossless(bytes)
    }

    @discardableResult
    private func save() -> Bool {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: support, withIntermediateDirectories: true)
            if backupFirst, fm.fileExists(atPath: file.path) {
                // An unreadable (or partly unreadable) shelf.json is never overwritten before it is kept.
                var bad = support.appendingPathComponent("shelf.json.bad-\(now())")
                var n = 1
                while fm.fileExists(atPath: bad.path) { bad = support.appendingPathComponent("shelf.json.bad-\(now())-\(n)"); n += 1 }
                try fm.copyItem(at: file, to: bad)
            }
            backupFirst = false
            try ShelfRules.encode(items).write(to: file, options: .atomic)
            lastError = nil
            return true
        } catch {
            lastError = "\(error)"
            return false
        }
    }

    // MARK: Adding

    private func bookmarkOptions() -> URL.BookmarkCreationOptions { scoped ? [.withSecurityScope] : [] }
    /// Never asks macOS to show anything or to reconnect a share: an original on an unmounted SMB or NFS volume reads as missing at once, instead of a network call that blocks the main thread
    /// from `heldPaths` and `checkMissing`.
    static func resolveOptions(scoped: Bool) -> URL.BookmarkResolutionOptions {
        scoped ? [.withSecurityScope, .withoutUI, .withoutMounting] : [.withoutUI, .withoutMounting]
    }

    /// The item for one original, or nil when it cannot be read or bookmarked.
    private func linkItem(_ url: URL) -> ShelfItem? {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .fileSizeKey])
        guard let bookmark = try? url.bookmarkData(options: bookmarkOptions(), includingResourceValuesForKeys: nil, relativeTo: nil) else { return nil }
        return ShelfItem(id: newID(), name: url.lastPathComponent, size: Int64(values?.fileSize ?? 0), folder: values?.isDirectory == true && values?.isPackage != true, copy: false, link: bookmark.base64EncodedString(), addedAt: now())
    }

    /// The item for a file with no original, copied into its own folder; nil when the copy cannot be made.
    private func copyItem(_ url: URL) -> ShelfItem? {
        let id = newID(), name = url.lastPathComponent
        let item = ShelfItem(id: id, name: name, size: Self.size(of: url), folder: false, copy: true, link: nil, addedAt: now())
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: folder(for: id), withIntermediateDirectories: true)
            try fm.copyItem(at: url, to: copyURL(item))
            return item
        } catch {
            try? fm.removeItem(at: folder(for: id))
            return nil
        }
    }

    private static func size(of url: URL) -> Int64 { Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }

    /// Whether a promised file is one the shelf already holds a copy of, or one already taken earlier in the same drop. The identity is name and bytes: the temp path is different every time, a renamed
    /// file is a different file, and size alone proves nothing, so the size only narrows the candidates and the bytes decide. A copy gone from disk is not a match, and a compare that cannot read
    /// either file is not one either (the file is then added, as before).
    private func isPromisedTwin(_ url: URL, size: Int64, earlier: [(name: String, size: Int64, url: URL)]) -> Bool {
        let fm = FileManager.default, name = url.lastPathComponent
        for e in earlier where e.name == name && e.size == size {
            if fm.contentsEqual(atPath: url.path, andPath: e.url.path) { return true }
        }
        for held in items where held.copy && held.name == name && held.size == size {
            let there = copyURL(held)
            if fm.fileExists(atPath: there.path), fm.contentsEqual(atPath: url.path, andPath: there.path) { return true }
        }
        return false
    }

    /// The paths of the originals the shelf already holds, so that the same file dropped twice is a duplicate even though two bookmarks of it are not the same bytes.
    private func heldPaths() -> Set<String> {
        Set(items.compactMap { $0.copy ? nil : bookmarkTarget($0)?.url.standardizedFileURL.path })
    }

    /// One word for each dropped file, in order (docs/SHELF-CONTRACT.md: added, duplicate, full or invalid). Writes shelf.json once.
    @discardableResult
    func add(_ incoming: [ShelfIncoming]) -> [ShelfAddResult] {
        var held = heldPaths()
        var candidates: [ShelfItem?] = []
        var precheck: [ShelfAddResult?] = []
        var taken: [(name: String, size: Int64, url: URL)] = []
        for one in incoming {
            switch one {
            case .file(let url):
                let path = url.standardizedFileURL.path
                if held.contains(path) { candidates.append(nil); precheck.append(.duplicate); continue }
                held.insert(path)
                let item = linkItem(url)
                candidates.append(item)
                precheck.append(item == nil ? .invalid : nil)
            case .temporary(let url):
                let size = Self.size(of: url)
                if isPromisedTwin(url, size: size, earlier: taken) { candidates.append(nil); precheck.append(.duplicate); continue }
                let item = copyItem(url)
                if item != nil { taken.append((url.lastPathComponent, size, url)) }
                candidates.append(item)
                precheck.append(item == nil ? .invalid : nil)
            }
        }
        let real = candidates.compactMap { $0 }
        let r = ShelfRules.add(items, real)
        var next = r.results.makeIterator()
        var results: [ShelfAddResult] = []
        for (k, c) in candidates.enumerated() {
            if let p = precheck[k] { results.append(p); continue }
            let word = next.next() ?? .invalid
            results.append(word)
            // A copy that was not added must not stay on disk.
            if word != .added, let c, c.copy { try? FileManager.default.removeItem(at: folder(for: c.id)) }
        }
        if r.results.contains(.added) {
            let before = items
            items = r.items
            if !save() {
                // shelf.json could not be written: what was added would vanish at the next launch, so nothing is added. The list goes back, the copies made in this call are removed,
                // and what would have been added is `invalid` (lastError says why).
                items = before
                for (k, c) in candidates.enumerated() where results[k] == .added {
                    if let c, c.copy { try? FileManager.default.removeItem(at: folder(for: c.id)) }
                    results[k] = .invalid
                }
            }
        }
        return results
    }

    // MARK: Using an item

    /// An item's bookmark resolved: its file, and whether macOS says the bookmark is stale. Nil when it does not resolve. The file may still be missing; ask `checkMissing`.
    private func bookmarkTarget(_ item: ShelfItem) -> (url: URL, stale: Bool)? {
        guard let text = item.link, let data = Data(base64Encoded: text) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: Self.resolveOptions(scoped: scoped), relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        return (url, stale)
    }

    /// Opens an item for use (a drag, Ask, Send, Show in Finder): its file with the security scope started. Nil when the file is gone. A stale bookmark is renewed.
    func open(_ caller: ShelfItem) -> ShelfAccess? {
        // The store's own item, not the caller's: its link is the one that gets renewed, and the caller's copy may be older.
        let item = items.first { $0.id == caller.id } ?? caller
        if item.copy {
            let url = copyURL(item)
            return FileManager.default.fileExists(atPath: url.path) ? ShelfAccess(url: url, scoped: false) : nil
        }
        guard let target = bookmarkTarget(item) else { return nil }
        let started = target.url.startAccessingSecurityScopedResource()
        guard FileManager.default.fileExists(atPath: target.url.path) else {
            if started { target.url.stopAccessingSecurityScopedResource() }
            return nil
        }
        if target.stale, let fresh = try? target.url.bookmarkData(options: bookmarkOptions(), includingResourceValuesForKeys: nil, relativeTo: nil),
           let at = items.firstIndex(where: { $0.id == item.id }) {
            items[at].link = fresh.base64EncodedString()
            save()
        }
        return ShelfAccess(url: target.url, scoped: started)
    }

    /// The ids of the items whose file is gone. Run when the shelf opens, never in the background.
    func checkMissing() -> Set<String> {
        var missing = Set<String>()
        for item in items {
            if let a = open(item) { a.end() } else { missing.insert(item.id) }
        }
        return missing
    }

    // MARK: Removing

    /// Removes an item. Its copy, if it has one, is deleted; an original is never touched.
    func remove(id: String) {
        guard let at = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: at)
        if item.copy { try? FileManager.default.removeItem(at: folder(for: item.id)) }
        save()
    }

    func clear() {
        for item in items where item.copy { try? FileManager.default.removeItem(at: folder(for: item.id)) }
        items = []
        save()
    }
}
