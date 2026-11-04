import Darwin
import Foundation

// The companion's files and conversation store (F3a-mac, Task 3), run through scripts/test-companion-store.sh. Every check works in a fresh folder
// under NM_COMPANION_TEST_ROOT and a dictionary-backed defaults store: nothing touches UserDefaults.standard, ~/Library or the shared store.
@MainActor
@main
enum CompanionStoreTests {
    /// The defaults as a dictionary (the CompanionDefaults pattern).
    final class DictDefaults: CompanionDefaults {
        var values: [String: Any] = [:]
        func object(forKey key: String) -> Any? { values[key] }
        func set(_ value: Any?, forKey key: String) { values[key] = value }
    }

    /// The temp root the script gives us. Refuses to run without it, or under a Library folder.
    static func testRoot() -> URL {
        guard let raw = ProcessInfo.processInfo.environment["NM_COMPANION_TEST_ROOT"], !raw.isEmpty, !raw.contains("/Library/") else {
            print("NM_COMPANION_TEST_ROOT is not set to a temp folder: run this through scripts/test-companion-store.sh")
            exit(2)
        }
        return URL(fileURLWithPath: raw, isDirectory: true)
    }

    /// A new folder under the test root, for one check.
    static func fresh(_ name: String) -> URL {
        let dir = testRoot().appendingPathComponent("\(name)-\(UUID().uuidString.lowercased())", isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// The companion folder under `dir` (the store's root), as the store will use it.
    static func companionRoot(_ dir: URL) -> URL {
        dir.appendingPathComponent("companion", isDirectory: true)
    }

    static func conversationsFolder(_ dir: URL) -> URL {
        companionRoot(dir).appendingPathComponent("conversations", isDirectory: true)
    }

    static func makeStore(_ dir: URL, defaults: DictDefaults = DictDefaults()) -> CompanionStore {
        CompanionStore(files: CompanionFiles(root: companionRoot(dir)), defaults: defaults, now: { 1_760_000_000_000 })
    }

    /// A conversation with one user message. `createdAt` stays 0 so `updatedAt` decides the order.
    static func conversation(_ id: String, updatedAt: Int = 1, pinned: Bool = false, text: String = "hello") -> CompanionConversation {
        CompanionConversation(
            id: id, title: "", pinned: pinned, createdAt: 0, updatedAt: updatedAt,
            messages: [CompanionMessage(role: "user", text: text, caption: "", files: [])]
        )
    }

    static func recordData(_ c: CompanionConversation) -> Data {
        try! JSONSerialization.data(withJSONObject: c.json, options: [.sortedKeys])
    }

    static func mode(_ url: URL) -> Int? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.posixPermissions] as? Int
    }

    static func size(_ url: URL) -> Int? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.size] as? Int
    }

    /// The lstat file type of `url` (a link is S_IFLNK), or nil when nothing is there.
    static func kind(_ url: URL) -> mode_t? {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return nil }
        return st.st_mode & S_IFMT
    }

    static func names(_ dir: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
    }

    /// Whether a save throws (the error's kind is not the point; a refused save is).
    static func refuses(_ body: () throws -> Void) -> Bool {
        do {
            try body()
            return false
        } catch {
            return true
        }
    }

    /// A result written from a background thread, read back after the wait.
    final class ResultBox: @unchecked Sendable {
        var value: Bool?
    }

    /// Runs `body` on a background thread and waits at most `seconds`. Nil means it did not finish in time, so a hang fails the run instead of
    /// stalling it.
    static func within(_ seconds: Double, _ body: @escaping @Sendable () -> Bool) -> Bool? {
        let box = ResultBox()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            box.value = body()
            done.signal()
        }
        guard done.wait(timeout: .now() + seconds) == .success else { return nil }
        return box.value
    }

    static func main() {
        CT.section("owner-only files")
        do {
            let dir = fresh("owner")
            let store = makeStore(dir)
            try! store.save(conversation("abc"))
            CT.check("companion folder is 0700", mode(companionRoot(dir)), 0o700)
            CT.check("conversations folder is 0700", mode(conversationsFolder(dir)), 0o700)
            CT.check("conversation file is 0600", mode(conversationsFolder(dir).appendingPathComponent("abc.json")), 0o600)
        }

        CT.section("a pre-existing companion folder with mode 0755 is corrected to 0700")
        do {
            let dir = fresh("modes")
            let root = companionRoot(dir)
            try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            CT.check("the folder starts at 0755", mode(root), 0o755)
            try! makeStore(dir).save(conversation("abc"))
            CT.check("companion is 0700 after a save", mode(root), 0o700)
            CT.check("conversations is 0700 after a save", mode(conversationsFolder(dir)), 0o700)
        }

        CT.section("atomic and exclusive writes")
        do {
            let dir = fresh("atomic")
            let store = makeStore(dir)
            try! store.save(conversation("abc", text: "first"))
            try! store.save(conversation("abc", text: "second"))
            CT.check("saving twice leaves one file and no temp file", names(conversationsFolder(dir)), ["abc.json"])
            let bytes = try! Data(contentsOf: conversationsFolder(dir).appendingPathComponent("abc.json"))
            let text = String(decoding: bytes, as: UTF8.self)
            CT.checkTrue("keys are written sorted", text.hasPrefix("{\"createdAt\""))
            CT.check("the second save wins", makeStore(dir).conversation(id: "abc")?.messages.first?.text, "second")
        }

        CT.section("a symbolic link is not followed and not replaced")
        do {
            let dir = fresh("symlink")
            try! FileManager.default.createDirectory(at: conversationsFolder(dir), withIntermediateDirectories: true)
            let elsewhere = dir.appendingPathComponent("elsewhere.json")
            let data = recordData(conversation("abc"))
            try! data.write(to: elsewhere)
            let link = conversationsFolder(dir).appendingPathComponent("abc.json")
            try! FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: elsewhere.path)
            let store = makeStore(dir)
            CT.checkTrue("a linked conversation reads as absent", store.conversation(id: "abc") == nil)
            CT.checkTrue("saving over the link throws", refuses { try store.save(conversation("abc", text: "changed")) })
            CT.check("abc.json is still a symbolic link", kind(link), S_IFLNK)
            CT.check("the link's target is unchanged", try? Data(contentsOf: elsewhere), data)
        }

        CT.section("a FIFO under a conversation name does not block the read")
        do {
            let dir = fresh("fifo")
            try! FileManager.default.createDirectory(at: conversationsFolder(dir), withIntermediateDirectories: true)
            let fifo = conversationsFolder(dir).appendingPathComponent("abc.json")
            CT.check("the FIFO is made", mkfifo(fifo.path, 0o600), 0)
            let files = CompanionFiles(root: companionRoot(dir))
            let absent = within(2) { files.read(fifo, maxBytes: CompanionFiles.conversationMax) == nil }
            CT.check("reading it returns within 2 s, as absent", absent, true)
            if absent == true {
                CT.checkTrue("the store reads it as absent", makeStore(dir).conversation(id: "abc") == nil)
            }
        }

        CT.section("a file over 8 MiB is read as absent and left alone")
        do {
            let dir = fresh("big")
            try! FileManager.default.createDirectory(at: conversationsFolder(dir), withIntermediateDirectories: true)
            let big = conversationsFolder(dir).appendingPathComponent("big.json")
            let bigBytes = 9 << 20
            try! Data(repeating: 0x20, count: bigBytes).write(to: big)
            let store = makeStore(dir)
            CT.check("the index leaves it out", store.conversations.count, 0)
            CT.checkTrue("reading it gives nothing", store.conversation(id: "big") == nil)
            CT.check("its size is unchanged", size(big), bigBytes)
            CT.checkTrue("saving over it throws", refuses { try store.save(conversation("big")) })
            CT.check("its size is still unchanged", size(big), bigBytes)
        }

        CT.section("a deeply nested conversation file is read as absent, without a crash")
        do {
            let dir = fresh("deep")
            try! FileManager.default.createDirectory(at: conversationsFolder(dir), withIntermediateDirectories: true)
            let nested = String(repeating: "[", count: 1000) + String(repeating: "]", count: 1000)
            try! Data("{\"id\":\"deep1\",\"x\":\(nested)}".utf8).write(to: conversationsFolder(dir).appendingPathComponent("deep1.json"))
            try! Data(("{\"id\":\"deep2\",\"x\":" + String(repeating: "[", count: 100_000)).utf8)
                .write(to: conversationsFolder(dir).appendingPathComponent("deep2.json"))
            let store = makeStore(dir)
            CT.checkTrue("depth 1000 reads as absent", store.conversation(id: "deep1") == nil)
            CT.checkTrue("100,000 open brackets read as absent", store.conversation(id: "deep2") == nil)
            CT.check("the index lists neither", store.conversations.count, 0)
        }

        CT.section("names and ids")
        do {
            let dir = fresh("names")
            let store = makeStore(dir)
            try! store.save(conversation("abc"))
            let record = recordData(conversation("abc"))
            try! record.write(to: conversationsFolder(dir).appendingPathComponent("Bad Name.json"))
            try! record.write(to: conversationsFolder(dir).appendingPathComponent("zzz.json"))
            let reopened = makeStore(dir)
            CT.check("only abc is listed, a bad name and a mismatched name are ignored", reopened.conversations.map { $0.id }, ["abc"])
            CT.checkTrue("the bad-name file is left alone", FileManager.default.fileExists(atPath: conversationsFolder(dir).appendingPathComponent("Bad Name.json").path))
            CT.checkTrue("a new id is valid", CompanionRecords.isId(reopened.newConversationId()))
        }

        CT.section("fifty kept, the rest deleted")
        do {
            let dir = fresh("keep")
            let store = makeStore(dir)
            for i in 1...52 {
                try! store.save(conversation(String(format: "c%02d", i), updatedAt: i))
            }
            let files = names(conversationsFolder(dir)).filter { $0.hasSuffix(".json") }
            CT.check("50 files kept", files.count, 50)
            CT.checkTrue("the two oldest are gone", !files.contains("c01.json") && !files.contains("c02.json"))
            CT.check("the list holds 50, newest first", store.conversations.count, 50)
            CT.check("newest first", store.conversations.first?.id, "c52")
        }

        CT.section("a pinned record is never evicted; the oldest unpinned go")
        do {
            let dir = fresh("pinned")
            let store = makeStore(dir)
            try! store.save(conversation("pin", updatedAt: 1, pinned: true))
            for i in 1...52 {
                try! store.save(conversation(String(format: "c%02d", i), updatedAt: i + 1))
            }
            let files = names(conversationsFolder(dir)).filter { $0.hasSuffix(".json") }
            CT.check("50 files kept", files.count, 50)
            CT.checkTrue("the pinned file stays", files.contains("pin.json"))
            CT.checkTrue("the three oldest unpinned are gone", !files.contains("c01.json") && !files.contains("c02.json") && !files.contains("c03.json"))
            CT.checkTrue("c04 is kept", files.contains("c04.json"))
            CT.check("the pinned record leads the list", store.conversations.first?.id, "pin")
        }

        CT.section("delete and delete all")
        do {
            let dir = fresh("delete")
            let store = makeStore(dir)
            try! store.save(conversation("abc"))
            try! store.save(conversation("def"))
            store.delete(id: "abc")
            CT.check("delete removes the file", names(conversationsFolder(dir)), ["def.json"])
            CT.check("delete drops it from the list", store.conversations.map { $0.id }, ["def"])
            try! Data("x".utf8).write(to: conversationsFolder(dir).appendingPathComponent("Bad Name.json"))
            try! Data("x".utf8).write(to: conversationsFolder(dir).appendingPathComponent("notes.txt"))
            store.deleteAll()
            CT.check("delete all removes every conversation file and leaves a bad name and an unrelated file",
                     names(conversationsFolder(dir)), ["Bad Name.json", "notes.txt"])
            CT.checkTrue("the list is empty", store.conversations.isEmpty)
        }

        CT.section("delete is honest: a file that stays is still listed, and the failed count is reported")
        do {
            let dir = fresh("honest")
            let store = makeStore(dir)
            try! store.save(conversation("abc"))
            try! store.save(conversation("def"))
            let folder = conversationsFolder(dir)
            try! FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.path)   // no unlink in a folder without write
            CT.check("delete reports one failure", store.delete(id: "abc"), 1)
            CT.check("the file is still there", names(folder), ["abc.json", "def.json"])
            CT.check("the row stays listed", Set(store.conversations.map { $0.id }), ["abc", "def"])
            CT.check("delete all reports both failures", store.deleteAll(), 2)
            CT.check("both rows stay listed", Set(store.conversations.map { $0.id }), ["abc", "def"])
            try! FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
            CT.check("once it can, delete reports none", store.delete(id: "abc"), 0)
            CT.check("and the row goes", store.conversations.map { $0.id }, ["def"])
            CT.check("an id with no file is deleted (ENOENT counts)", store.delete(id: "zzz"), 0)
            CT.check("delete all reports none", store.deleteAll(), 0)
            CT.checkTrue("and the list is empty", store.conversations.isEmpty && names(folder).isEmpty)
        }

        CT.section("a file that cannot be unlinked is reported even when its record could not be read")
        do {
            let dir = fresh("stuck")
            let folder = conversationsFolder(dir)
            try! FileManager.default.createDirectory(at: folder.appendingPathComponent("abc.json"), withIntermediateDirectories: true)
            try! Data("x".utf8).write(to: folder.appendingPathComponent("abc.json/inner"))
            let store = makeStore(dir)
            CT.check("delete reports the failure", store.delete(id: "abc"), 1)
            CT.check("delete all reports it too", store.deleteAll(), 1)
            CT.check("the folder is still there", kind(folder.appendingPathComponent("abc.json")), S_IFDIR)
        }

        CT.section("a folder that cannot be listed does not read as nothing saved")
        do {
            let dir = fresh("unlistable")
            let store = makeStore(dir)
            try! store.save(conversation("abc"))
            let folder = conversationsFolder(dir)
            try! FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: folder.path)
            let failed = store.deleteAll()
            try! FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
            CT.checkTrue("delete all reports a failure", failed >= 1)
            CT.check("the row stays listed", store.conversations.map { $0.id }, ["abc"])
            CT.check("the file is still there", names(folder), ["abc.json"])
            CT.check("a folder that does not exist is no failure", makeStore(fresh("nofolder")).deleteAll(), 0)
        }

        CT.section("stale temp files are swept when the store opens and when delete all runs")
        do {
            let dir = fresh("temps")
            let folder = conversationsFolder(dir)
            try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let stale = folder.appendingPathComponent(".x.json.\(UUID().uuidString.lowercased()).tmp")
            try! Data("half".utf8).write(to: stale)
            try! Data("keep".utf8).write(to: folder.appendingPathComponent("notes.txt"))
            let store = makeStore(dir)
            CT.check("opening the store removes it", names(folder), ["notes.txt"])
            try! store.save(conversation("abc"))
            let later = folder.appendingPathComponent(".abc.json.\(UUID().uuidString.lowercased()).tmp")
            try! Data("half".utf8).write(to: later)
            CT.check("delete all removes it, and only conversation files and temp files", store.deleteAll(), 0)
            CT.check("what is left is the unrelated file", names(folder), ["notes.txt"])
        }

        CT.section("fifty pinned: a new chat is refused instead of being saved and evicted")
        do {
            let dir = fresh("full")
            let store = makeStore(dir)
            for i in 1...50 { try! store.save(conversation(String(format: "p%02d", i), updatedAt: i, pinned: true)) }
            var thrown: CompanionStoreError?
            do { try store.save(conversation("new1", updatedAt: 99)) } catch { thrown = error as? CompanionStoreError }
            CT.check("the save throws full", thrown, .full)
            CT.check("fifty files stay", names(conversationsFolder(dir)).filter { $0.hasSuffix(".json") }.count, 50)
            CT.checkTrue("the new one is not among them", !names(conversationsFolder(dir)).contains("new1.json"))
            CT.check("the list still holds the fifty", store.conversations.count, 50)
            CT.checkTrue("a pinned one can still be saved again", !refuses { try store.save(conversation("p01", updatedAt: 100, pinned: true)) })
        }

        CT.section("the guards: nothing outside the conversations folder is written, read or deleted")
        do {
            let dir = fresh("guards")
            let files = CompanionFiles(root: companionRoot(dir))
            let outside = companionRoot(dir).appendingPathComponent("outside.json")
            let nested = conversationsFolder(dir).appendingPathComponent("sub/x.json")
            CT.checkTrue("a write outside the root throws", refuses { try files.write(Data("x".utf8), to: outside) })
            CT.checkTrue("a write in a sub-folder throws", refuses { try files.write(Data("x".utf8), to: nested) })
            CT.checkTrue("a write to the temp folder of the OS throws", refuses { try files.write(Data("x".utf8), to: URL(fileURLWithPath: "/tmp/nm-companion-outside.json")) })
            CT.checkTrue("nothing was created outside", !FileManager.default.fileExists(atPath: outside.path) && !FileManager.default.fileExists(atPath: nested.path))
            for bad in ["../x", "a/b", "", String(repeating: "a", count: 65), "abc\n", "ABC", "a.b", "-a"] {
                CT.checkTrue("conversationURL is nil for \(bad.debugDescription)", files.conversationURL(bad) == nil)
            }
            CT.checkTrue("a 64-character id is a path", files.conversationURL(String(repeating: "a", count: 64)) != nil)
            let victim = companionRoot(dir).appendingPathComponent("victim.json")
            try! FileManager.default.createDirectory(at: companionRoot(dir), withIntermediateDirectories: true)
            try! Data("mine".utf8).write(to: victim)
            let store = makeStore(dir)
            CT.check("delete of ../victim reports nothing failed", store.delete(id: "../victim"), 0)
            CT.check("the file outside is left alone", try? Data(contentsOf: victim), Data("mine".utf8))
            CT.checkTrue("reading ../victim gives nothing", store.conversation(id: "../victim") == nil)
        }

        CT.section("a failed rename leaves no temp file; an overwritten file ends at 0600")
        do {
            let dir = fresh("rename-fail")
            let folder = conversationsFolder(dir)
            try! FileManager.default.createDirectory(at: folder.appendingPathComponent("abc.json"), withIntermediateDirectories: true)
            let files = CompanionFiles(root: companionRoot(dir))
            CT.checkTrue("writing over a folder throws", refuses { try files.write(Data("x".utf8), to: folder.appendingPathComponent("abc.json")) })
            CT.check("no temp file is left", names(folder), ["abc.json"])
            let dir2 = fresh("rewrite")
            let target = conversationsFolder(dir2).appendingPathComponent("abc.json")
            try! FileManager.default.createDirectory(at: conversationsFolder(dir2), withIntermediateDirectories: true)
            try! recordData(conversation("abc", text: "old")).write(to: target)
            try! FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: target.path)
            CT.check("the planted file is 0644", mode(target), 0o644)
            try! makeStore(dir2).save(conversation("abc", text: "new"))
            CT.check("after a save it is 0600", mode(target), 0o600)
            CT.check("and holds the new text", makeStore(dir2).conversation(id: "abc")?.messages.first?.text, "new")
        }

        CT.section("reading never writes: 55 files are listed as 50 and all 55 stay on disk")
        do {
            let dir = fresh("readonly")
            let folder = conversationsFolder(dir)
            try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for i in 1...55 {
                try! recordData(conversation(String(format: "c%02d", i), updatedAt: i)).write(to: folder.appendingPathComponent(String(format: "c%02d.json", i)))
            }
            let before = names(folder)
            let store = makeStore(dir)
            CT.check("the list holds 50", store.conversations.count, 50)
            CT.check("all 55 files are still there", names(folder), before)
            CT.check("55 of them", before.count, 55)
        }

        CT.section("rename and pin survive a new store")
        do {
            let dir = fresh("rename")
            let store = makeStore(dir)
            try! store.save(conversation("abc"))
            store.rename(id: "abc", title: "Trip plans")
            store.setPinned(id: "abc", true)
            let reopened = makeStore(dir)
            CT.check("the title survives", reopened.conversation(id: "abc")?.title, "Trip plans")
            CT.check("the pin survives", reopened.conversation(id: "abc")?.pinned, true)
            CT.check("a pinned conversation leads the list", reopened.conversations.first?.id, "abc")
        }

        CT.section("settings: defaults, update, clean")
        do {
            let defaults = DictDefaults()
            let store = makeStore(fresh("settings"), defaults: defaults)
            CT.check("humor defaults to little", store.settings.humor, "little")
            CT.check("See my sessions defaults to on", store.settings.seeSessions, true)
            CT.check("no cloud notice yet", store.settings.cloudNoticeShown, [])
            store.update { $0.humor = "more"; $0.seeSessions = false }
            CT.check("humor is stored", defaults.values["companion.humor"] as? String, "more")
            CT.check("See my sessions is stored", defaults.values["companion.seeSessions"] as? Bool, false)
            CT.checkTrue("only the stored keys are written", Set(defaults.values.keys).isSubset(of: Set(CompanionStore.storedKeys)))
            defaults.values["companion.humor"] = "loud"
            CT.check("an unknown humor reads as little", makeStore(fresh("cleanup"), defaults: defaults).settings.humor, "little")
        }

        CT.section("no message and no path in the defaults")
        do {
            let defaults = DictDefaults()
            let store = makeStore(fresh("privacy"), defaults: defaults)
            let c = CompanionConversation(
                id: "abc", title: "", pinned: false, createdAt: 0, updatedAt: 1,
                messages: [CompanionMessage(role: "user", text: "MARKER-MESSAGE", caption: "MARKER-CAPTION", files: ["/Users/sam/MARKER/notes.txt"])]
            )
            try! store.save(c)
            CT.check("saving writes no default", defaults.values.isEmpty, true)
            let leaked = defaults.values.values.contains { "\($0)".contains("MARKER") }
            CT.checkTrue("no value in the defaults holds a marker", !leaked)
        }

        CT.section("a leading U+FEFF survives a save and a read")
        do {
            let dir = fresh("feff")
            let text = "\u{FEFF}hello"
            try! makeStore(dir).save(conversation("abc", text: text))
            CT.check("the message text round-trips", makeStore(dir).conversation(id: "abc")?.messages.first?.text, text)
        }

        CT.section("a conversation too big to read back is refused")
        do {
            let dir = fresh("huge")
            let store = makeStore(dir)
            let huge = CompanionConversation(
                id: "huge", title: "", pinned: false, createdAt: 0, updatedAt: 1,
                messages: (0..<100).map { _ in CompanionMessage(role: "user", text: String(repeating: "a", count: 100_000), caption: "", files: []) }
            )
            CT.checkTrue("the save throws", refuses { try store.save(huge) })
            CT.checkTrue("no file is written", !FileManager.default.fileExists(atPath: conversationsFolder(dir).appendingPathComponent("huge.json").path))
        }

        CT.section("the frozen marker")
        CT.check("the marker is the frozen name", CompanionFiles.marker, "NM_COMPANION_STORE_ACTIVE")
        CT.checkTrue("the marker is 16 bytes or more", CompanionFiles.marker.utf8.count >= 16)

        CT.finish()
    }
}
