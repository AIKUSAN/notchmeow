import Foundation

// The companion's conversation records and settings (F3a-mac, Task 2): titleOf, conversationClean, conversationsKeep and cleanCompanionSettings. A port
// of shared/companion-core.js (the specification; docs/COMPANION-CONTRACT.md, "Conversation records" and "Settings"), replayed against
// tests/fixtures/companion/ by scripts/test-companion-rules.sh. Pure Foundation: no clock, no files, no defaults.
//
// Porting rules: lengths are code points (unicodeScalars); a time or a count is a JSON safe integer (CompanionText.wholeNumber); a JSON boolean is
// never a text or a number (ProjectsRegistry.isTrue, isJSONBool); text order is by UTF-16 code units (ProjectsRules.utf16Less); every structural
// split and trim works on scalars, never on Characters, and is a loop, never a backtracking regex.
struct CompanionMessage: Equatable, Sendable {
    var role: String
    var text: String
    var caption: String
    var files: [String]
}

/// A stored conversation as the core cleans it. `json` is the file's content with version 1. Only the set of keys is significant: a stored file is
/// written with sorted keys, and the reader never depends on order.
struct CompanionConversation: Equatable, Sendable {
    var id: String
    var title: String
    var pinned: Bool
    var createdAt: Int
    var updatedAt: Int
    var messages: [CompanionMessage]

    var json: [String: Any] {
        let list: [[String: Any]] = messages.map { m in
            ["role": m.role, "text": m.text, "caption": m.caption, "files": m.files] as [String: Any]
        }
        return [
            "version": 1, "id": id, "title": title, "pinned": pinned, "createdAt": createdAt, "updatedAt": updatedAt, "messages": list,
        ] as [String: Any]
    }
}

/// The Companion settings as the core cleans them (the companion.* keys on the Mac). `json` holds the seven keys; their order is not significant.
struct CompanionSettings: Equatable, Sendable {
    var humor: String
    var useMemory: Bool
    var seeSessions: Bool
    var polishRecap: Bool
    var recapDismissals: Int
    var lastRecapDay: String
    var cloudNoticeShown: [String]

    static let humorLevels = ["off", "little", "more"]
    static let recapMuteAt = 2

    /// The one clean-up rule for the settings. Only the stated values survive; anything else is the default. A list or any non-object is all defaults.
    static func clean(_ raw: Any?) -> CompanionSettings {
        let o = raw as? [String: Any] ?? [:]
        let humor = (o["humor"] as? String).flatMap { humorLevels.contains($0) ? $0 : nil } ?? "little"
        // Only a JSON `false` switches a default-on setting off: 0, "no" and null keep it on.
        let useMemory = !(ProjectsRegistry.isJSONBool(o["useMemory"]) && !ProjectsRegistry.isTrue(o["useMemory"]))
        let seeSessions = !(ProjectsRegistry.isJSONBool(o["seeSessions"]) && !ProjectsRegistry.isTrue(o["seeSessions"]))
        let dismissals = CompanionText.wholeNumber(o["recapDismissals"]).flatMap { $0 > 0 ? min(recapMuteAt, $0) : nil } ?? 0
        let shown = ((o["cloudNoticeShown"] as? [Any]) ?? []).compactMap { $0 as? String }.filter(CompanionRecords.isProvider)
        // Provider ids are ASCII (isProvider), so byte order is the UTF-16 code-unit order the core sorts by.
        let providers = Array(Set(shown)).sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }.prefix(16)
        return CompanionSettings(
            humor: humor,
            useMemory: useMemory,
            seeSessions: seeSessions,
            polishRecap: ProjectsRegistry.isTrue(o["polishRecap"]),
            recapDismissals: dismissals,
            lastRecapDay: CompanionText.isDay(o["lastRecapDay"]) ? (o["lastRecapDay"] as? String ?? "") : "",
            cloudNoticeShown: Array(providers)
        )
    }

    /// The settings as the store writes them: the seven keys.
    var json: [String: Any] {
        [
            "humor": humor, "useMemory": useMemory, "seeSessions": seeSessions, "polishRecap": polishRecap,
            "recapDismissals": recapDismissals, "lastRecapDay": lastRecapDay, "cloudNoticeShown": cloudNoticeShown,
        ] as [String: Any]
    }
}

enum CompanionRecords {
    static let conversationsMax = 50
    static let titleMax = 40
    static let messagesMax = 1000
    static let messageTextMax = 100_000
    static let captionMax = 80
    static let fileNameMax = 60
    static let filesMax = 10
    static let newChat = "New chat"

    typealias Scalars = CompanionText.Scalars

    // MARK: - Ids and providers

    /// `^[a-z0-9][a-z0-9-]{0,63}$`: a conversation id.
    static func isId(_ s: String) -> Bool {
        let u = CompanionText.sc(s)
        guard let first = u.first, u.count <= 64, isLowerOrDigit(first) else { return false }
        return u.dropFirst().allSatisfy { isLowerOrDigit($0) || $0 == "-" }
    }

    /// `^[a-zA-Z][a-zA-Z0-9_-]{0,31}$`: a provider id in `cloudNoticeShown`.
    static func isProvider(_ s: String) -> Bool {
        let u = CompanionText.sc(s)
        guard let first = u.first, u.count <= 32, CompanionText.isASCIILetter(first) else { return false }
        return u.dropFirst().allSatisfy { CompanionText.isAlnum($0) || $0 == "_" || $0 == "-" }
    }

    private static func isLowerOrDigit(_ u: Unicode.Scalar) -> Bool {
        (97...122).contains(u.value) || CompanionText.isDigit(u)
    }

    // MARK: - Text

    /// The core's oneLine, on scalars: a line break or tab (CR, LF, TAB, U+2028, U+2029) becomes a space, the invisible characters go with no space,
    /// every run of JavaScript whitespace becomes one space, and the ends are trimmed. After the fold a space is the only whitespace left, so the trim
    /// drops spaces alone.
    static func oneLine(_ u: Scalars) -> Scalars {
        var out: Scalars = []
        out.reserveCapacity(u.count)
        var space = false
        for c in u {
            let fold = c == "\r" || c == "\n" || c == "\t" || c.value == 0x2028 || c.value == 0x2029
            if fold || (!CompanionText.isInvisible(c) && ProjectsRules.isJSSpace(c)) {
                if !space { out.append(" "); space = true }
            } else if !CompanionText.isInvisible(c) {
                out.append(c)
                space = false
            }
        }
        var a = 0, b = out.count
        while a < b, out[a] == " " { a += 1 }
        while b > a, out[b - 1] == " " { b -= 1 }
        return Array(out[a..<b])
    }

    /// A text cut to `max` code points, on scalars: kept whole when it fits, else `max - 1` code points and `…` (the core's cutTo).
    static func cutScalars(_ u: Scalars, _ max: Int) -> Scalars {
        guard u.count > max else { return u }
        return Array(u.prefix(max - 1)) + ["…"]
    }

    /// The text of a user message as its title: one line, each word through `shownWord` (a secret word dropped; a path keeps its last part), at most
    /// 40 code points; `New chat` when nothing is left or the value is not text. Words are judged on scalars (`CompanionText.shown`, the same rule).
    static func titleOf(_ text: Any?) -> String {
        guard let s = text as? String else { return newChat }
        let pieces = CompanionText.split(oneLine(CompanionText.sc(s))) { $0 == " " }
        var title: Scalars = []
        for piece in pieces {
            let shown = CompanionText.shown(piece)
            guard !shown.isEmpty else { continue }
            if !title.isEmpty { title.append(" ") }
            title += shown
        }
        return title.isEmpty ? newChat : CompanionText.text(cutScalars(title, titleMax))
    }

    /// A time or a count: a safe whole number of 0 or more, else 0 (a decimal, a negative, 1e300, a text).
    static func timeOf(_ v: Any?) -> Int {
        guard let n = CompanionText.wholeNumber(v), n >= 0 else { return 0 }
        return n
    }

    // MARK: - Records

    /// A stored conversation read and cleaned, or nil when the raw value is not an object or its id is not a valid one. Never throws.
    static func clean(_ raw: Any?) -> CompanionConversation? {
        guard let o = raw as? [String: Any], let id = o["id"] as? String, isId(id) else { return nil }
        let listed = ((o["messages"] as? [Any]) ?? []).compactMap { $0 as? [String: Any] }.filter { m in
            guard let role = m["role"] as? String, role == "user" || role == "assistant" else { return false }
            return m["text"] is String
        }
        let messages: [CompanionMessage] = listed.suffix(messagesMax).map { m in
            let role = m["role"] as? String ?? ""
            let text = CompanionText.cutTo(m["text"] as? String ?? "", messageTextMax)
            let caption = (m["caption"] as? String).map { CompanionText.text(cutScalars(oneLine(CompanionText.sc($0)), captionMax)) } ?? ""
            let names = ((m["files"] as? [Any]) ?? []).compactMap { $0 as? String }
                .map { oneLine(CompanionText.lastPartOf(CompanionText.sc($0))) }
                .filter { !$0.isEmpty }
                .map { cutScalars($0, fileNameMax) }
            return CompanionMessage(role: role, text: text, caption: caption, files: names.prefix(filesMax).map { CompanionText.text($0) })
        }
        let first = messages.first { $0.role == "user" }
        let createdAt = timeOf(o["createdAt"])
        let titled = titleOf(o["title"])
        return CompanionConversation(
            id: id,
            title: titled != newChat ? titled : titleOf(first?.text),
            pinned: ProjectsRegistry.isTrue(o["pinned"]),
            createdAt: createdAt,
            updatedAt: max(timeOf(o["updatedAt"]), createdAt),
            messages: messages
        )
    }

    /// Which conversations stay: at most 50. An entry is `{id, pinned, updatedAt}`; an invalid id is skipped, and a repeated id keeps its newer
    /// entry (the later one on a tie). `keep` is the display order (pinned first, newest first, then by id in UTF-16 order); `evict` is the rest,
    /// the last of the order first, so the oldest unpinned goes first. Never throws.
    static func keep(_ entries: Any?) -> (keep: [String], evict: [String]) {
        guard let list = entries as? [Any] else { return ([], []) }
        var best: [String: (pinned: Bool, updatedAt: Int)] = [:]
        for case let e as [String: Any] in list {
            guard let id = e["id"] as? String, isId(id) else { continue }
            let row = (pinned: ProjectsRegistry.isTrue(e["pinned"]), updatedAt: timeOf(e["updatedAt"]))
            if let old = best[id], row.updatedAt < old.updatedAt { continue }
            best[id] = row
        }
        let rows = best.map { (id: $0.key, pinned: $0.value.pinned, updatedAt: $0.value.updatedAt) }.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
            // Ids are ASCII (isId), so byte order is the UTF-16 code-unit order the core sorts by.
            return a.id.utf8.lexicographicallyPrecedes(b.id.utf8)
        }
        let ids = rows.map { $0.id }
        return (keep: Array(ids.prefix(conversationsMax)), evict: Array(ids.dropFirst(conversationsMax).reversed()))
    }
}
