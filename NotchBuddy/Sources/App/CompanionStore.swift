import Combine
import Foundation

// The companion's conversation store (F3a-mac, Task 3): the saved conversations as files (CompanionFiles), the three companion.* defaults, and the list
// the chat shows. It reads and writes what CompanionRecords and CompanionSettings decide (replayed by scripts/test-companion-rules.sh); the rules are
// not here. Nothing here logs, and no message, prompt, reply or path goes into the defaults. Nothing runs while the chat is idle: no timer, no watcher.

/// The defaults the store reads and writes: UserDefaults in the app, a dictionary in the tests.
protocol CompanionDefaults {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: CompanionDefaults {}

/// Why a save was refused. Carries no text.
enum CompanionStoreError: Error, Equatable {
    /// The conversation's id is not a valid one.
    case invalidId
    /// A file is already there that is a link, too large or unreadable: never overwritten here.
    case notOverwritable
    /// The record is over the read limit, so it could not be read back.
    case tooLarge
    /// The 50 kept are all pinned: the new conversation would be saved and evicted at once, so it is refused.
    case full
}

@MainActor
final class CompanionStore: ObservableObject {
    /// The marker is `CompanionFiles.marker`; the store's own names are the three defaults keys below.
    static let humorKey = "companion.humor"
    static let seeSessionsKey = "companion.seeSessions"
    static let cloudNoticeKey = "companion.cloudNoticeShown"
    static let storedKeys = [humorKey, seeSessionsKey, cloudNoticeKey]

    static let shared = CompanionStore(
        files: .standard(), defaults: UserDefaults.standard, now: { Int(Date().timeIntervalSince1970 * 1000) }
    )

    /// The kept conversations (at most 50, `CompanionRecords.keep`), pinned first, newest first.
    @Published private(set) var conversations: [CompanionConversation] = []
    @Published private(set) var settings: CompanionSettings

    let files: CompanionFiles
    private let defaults: CompanionDefaults
    /// Every readable record on disk, in memory. `conversations` is its kept part; the rest wait for the next save to delete them.
    private var records: [CompanionConversation] = []

    /// Reads the folder once, here: `static let shared` is itself created on first use, so this is the first use. Reading never writes a conversation (it only
    /// sweeps the temp files a crashed write left).
    /// `now` is kept for the plan's signature; F3a-mem-mac stamps with it. The store itself stamps nothing.
    init(files: CompanionFiles, defaults: CompanionDefaults, now: @escaping () -> Int) {
        self.files = files
        self.defaults = defaults
        var raw: [String: Any] = [:]
        if let v = defaults.object(forKey: Self.humorKey) { raw["humor"] = v }
        if let v = defaults.object(forKey: Self.seeSessionsKey) { raw["seeSessions"] = v }
        if let v = defaults.object(forKey: Self.cloudNoticeKey) { raw["cloudNoticeShown"] = v }
        settings = CompanionSettings.clean(raw)
        files.sweepTemps()
        records = (files.conversationIds() ?? []).compactMap { readRecord($0) }
        publish(order().keep)
    }

    /// The conversation stored under `id`, read from its file; nil when the id is not valid, the file is absent, a link, too large, unreadable, or
    /// holds another id than its name.
    func conversation(id: String) -> CompanionConversation? {
        readRecord(id)
    }

    /// Saves `c` as `conversations/<id>.json` (cleaned, keys sorted, written atomically), then keeps the 50 first in display order and deletes the
    /// files of the rest. Throws, and writes nothing, when the id is not valid, a file under that id is a link or cannot be read back, or the record
    /// is too large to read back.
    func save(_ c: CompanionConversation) throws {
        guard let record = CompanionRecords.clean(c.json), let url = files.conversationURL(record.id) else {
            throw CompanionStoreError.invalidId
        }
        if files.exists(url), readRecord(record.id) == nil { throw CompanionStoreError.notOverwritable }
        let data = try JSONSerialization.data(withJSONObject: record.json, options: [.sortedKeys])
        guard data.count <= CompanionFiles.conversationMax else { throw CompanionStoreError.tooLarge }
        try files.write(data, to: url)
        records.removeAll { $0.id == record.id }
        records.append(record)
        if settle().contains(record.id) { throw CompanionStoreError.full }
    }

    /// Renames a stored conversation to `title` (cleaned by `CompanionRecords.titleOf`); its time stays. A failed write leaves it as it was.
    func rename(id: String, title: String) {
        guard var c = records.first(where: { $0.id == id }) else { return }
        c.title = CompanionRecords.titleOf(title)
        try? save(c)
    }

    /// Pins or unpins a stored conversation; its time stays. A failed write leaves it as it was.
    func setPinned(id: String, _ pinned: Bool) {
        guard var c = records.first(where: { $0.id == id }) else { return }
        c.pinned = pinned
        try? save(c)
    }

    /// Deletes one conversation's file (a link is removed, never followed), whether or not its record could be read. Returns 1 when the file stays (its
    /// row stays listed too), else 0; a file that was not there counts as deleted.
    @discardableResult
    func delete(id: String) -> Int {
        guard let url = files.conversationURL(id) else { return 0 }
        guard files.delete(url) == 0 else { return 1 }
        records.removeAll { $0.id == id }
        settle()
        return 0
    }

    /// Deletes every conversation file the store can name, and any temp file a crash left. The Companion's own store only: no other file is touched.
    /// Returns how many files stay (each stays listed), plus one when the folder could not be listed; the records it knows are still tried.
    @discardableResult
    func deleteAll() -> Int {
        let listed = files.conversationIds()
        var failed = listed == nil ? 1 : 0
        for id in Set((listed ?? []) + records.map { $0.id }) {
            guard let url = files.conversationURL(id) else { continue }
            if files.delete(url) == 0 { records.removeAll { $0.id == id } } else { failed += 1 }
        }
        files.sweepTemps()
        settle()
        return failed
    }

    /// Changes the settings: the change is cleaned, then the three stored keys are written. Nothing else is written.
    func update(_ change: (inout CompanionSettings) -> Void) {
        var next = settings
        change(&next)
        settings = CompanionSettings.clean(next.json)
        defaults.set(settings.humor, forKey: Self.humorKey)
        defaults.set(settings.seeSessions, forKey: Self.seeSessionsKey)
        defaults.set(settings.cloudNoticeShown, forKey: Self.cloudNoticeKey)
    }

    func newConversationId() -> String {
        UUID().uuidString.lowercased()
    }

    // MARK: - Private

    /// The record under `id`, read and cleaned. Its own id must be its name: a file `abc.json` that says `xyz` is not a record of this store.
    private func readRecord(_ id: String) -> CompanionConversation? {
        guard let url = files.conversationURL(id), let data = files.read(url, maxBytes: CompanionFiles.conversationMax),
              let raw = Self.jsonObject(data), let record = CompanionRecords.clean(raw), record.id == id
        else { return nil }
        return record
    }

    /// The kept ids in display order, and the ids past the 50.
    private func order() -> (keep: [String], evict: [String]) {
        CompanionRecords.keep(records.map { ["id": $0.id, "pinned": $0.pinned, "updatedAt": $0.updatedAt] as [String: Any] })
    }

    /// Drops the records past the 50, deletes their files, and publishes the kept list. Only a save or a delete calls this. Returns the ids it dropped.
    @discardableResult
    private func settle() -> [String] {
        let order = order()
        for id in order.evict {
            if let url = files.conversationURL(id) { files.delete(url) }
        }
        records.removeAll { order.evict.contains($0.id) }
        publish(order.keep)
        return order.evict
    }

    private func publish(_ ids: [String]) {
        let byId = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        conversations = ids.compactMap { byId[$0] }
    }

    /// A stored file's JSON as Foundation values. JSONSerialization drops one leading U+FEFF from a string, and a message's text keeps it, so the
    /// file is decoded here, where a string keeps every character.
    private static func jsonObject(_ data: Data) -> Any? {
        (try? JSONDecoder().decode(StoredJSON.self, from: data))?.foundation
    }
}

/// One JSON value, told apart in this order: null, Bool, number, text, list, object. Its Foundation values are what CompanionRecords.clean reads:
/// a Bool is an NSNumber holding a CFBoolean (ProjectsRegistry.isJSONBool), a number is a Double.
private enum StoredJSON: Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case text(String)
    case list([StoredJSON])
    case object([String: StoredJSON])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let d = try? c.decode(Double.self) {
            self = .number(d)
        } else if let s = try? c.decode(String.self) {
            self = .text(s)
        } else if let l = try? c.decode([StoredJSON].self) {
            self = .list(l)
        } else {
            self = .object(try c.decode([String: StoredJSON].self))
        }
    }

    var foundation: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return NSNumber(value: b)
        case .number(let d): return NSNumber(value: d)
        case .text(let s): return s
        case .list(let l): return l.map { $0.foundation }
        case .object(let o): return o.mapValues { $0.foundation }
        }
    }
}
