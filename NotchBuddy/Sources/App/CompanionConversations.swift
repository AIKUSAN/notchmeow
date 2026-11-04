import Foundation

// The stored conversations' pure rules (F3a-mac, Task 5): which chat rows a stored conversation keeps, the text a stored message gives the model (its
// file names as lines, never a file's text), and the day a row shows. No state, no files and no clock: the caller passes the time. Pure Foundation.
// Replayed by scripts/test-companion-conversations.sh.
enum CompanionChatRules {
    /// One row of the chat as the store sees it. `status` marks a sidekick status row (its question or its answer): never stored.
    struct Row: Equatable {
        /// The chat row this is (its `ChatMessage.id`); a row made without one has its own.
        var id = UUID()
        let role: String
        let text: String
        let caption: String?
        let files: [String]
        let status: Bool
    }

    /// The rows a stored conversation keeps, in order: not a status row, not an empty one, and not one of `excluding` (the rows that were on screen when the
    /// chat's stored copy was deleted: they are not written back). Rows are named by id, so a row removed later does not move the others.
    static func messages(_ rows: [Row], excluding: Set<UUID> = []) -> [CompanionMessage] {
        rows.filter { !excluding.contains($0.id) && !$0.status && !$0.text.isEmpty }.map { row in
            CompanionMessage(role: row.role, text: row.text, caption: row.caption ?? "", files: row.files)
        }
    }

    /// A stored message as the chat restores it: the words the model is sent (file lines added), the caption and the file names. The words on screen
    /// are the stored text itself.
    struct Restored: Equatable {
        let role: String
        let modelText: String
        let caption: String?
        let files: [String]
    }

    /// The stored messages as the chat restores them, in order.
    static func restored(_ messages: [CompanionMessage]) -> [Restored] {
        messages.map { m in
            Restored(role: m.role, modelText: modelText(m), caption: m.caption.isEmpty ? nil : m.caption, files: m.files)
        }
    }

    /// The words a conversation's title is made from: a quick Explain's first message is its selection inside one exact `<text>\n…\n</text>` wrapper, which stays in
    /// the stored text (the labelling must survive the history) but is not the title. Anything that is not exactly one full wrapper is as it is.
    static func titleSource(_ text: String?) -> String? {
        guard let text, text.hasPrefix("<text>\n"), text.hasSuffix("\n</text>"), text.utf8.count >= 15 else { return text }
        return String(text.dropFirst(7).dropLast(8))
    }

    /// A conversation opens only when no reply is streaming or about to (`busy`: the chat is thinking, as it is from the send until the reply has started; an error state is not busy): the reply's
    /// own finish would take back a turn of the opened chat.
    static func canOpen(streaming: Bool, busy: Bool) -> Bool {
        !streaming && !busy
    }

    /// What the model is sent for a stored message: its words, then one line per file, named only. A file's text is never kept, so it is never sent.
    static func modelText(_ message: CompanionMessage) -> String {
        message.files.reduce(message.text) { $0 + "\n(file: \($1), not kept)" }
    }

    /// The day a row shows: "Today", "Yesterday", or "MMM d" in `calendar`'s day, the month in English (en_US_POSIX).
    static func dayLabel(updatedAt: Int, now: Int, calendar: Calendar) -> String {
        let day = Date(timeIntervalSince1970: TimeInterval(updatedAt) / 1000)
        let today = Date(timeIntervalSince1970: TimeInterval(now) / 1000)
        if calendar.isDate(day, inSameDayAs: today) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMM d"
        return formatter.string(from: day)
    }
}
