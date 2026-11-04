import Foundation

// What an approval inside a chat is made of: the card's words, the queue of requests waiting for a click, and whether
// NotchMeow's hooks are in Claude Code's settings (without them every Agent step is refused).

#if !APPSTORE

/// One step Claude Code is waiting to take, shown as a card in the chat.
struct ChatApproval: Sendable, Equatable, Identifiable {
    let id: UUID
    var sessionID: String
    var tool: String
    /// "Bash · npm test", "Write · /work/notes.txt": what Allow actually authorises.
    var target: String
}

enum ChatApprovalText {
    /// Ordered by how specific the field is, so an unfamiliar tool still shows whatever identifies its target.
    static let fields = ["command", "file_path", "path", "url", "query", "pattern", "prompt"]

    /// "Approving Write tells you nothing; approving `Write · /work/.env` tells you everything."
    static func target(tool: String, input: [String: Any]) -> String {
        for field in fields {
            if let value = (input[field] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return "\(tool) · \(value)"
            }
        }
        return tool
    }
}

/// Requests wait here in the order they arrived (parallel tool calls ask together); the card shows the first.
/// `Token` is whatever the caller needs to answer one (the hook's connection).
struct ChatApprovalQueue<Token: Sendable>: Sendable {
    struct Entry: Sendable {
        var approval: ChatApproval
        var token: Token
    }

    private(set) var entries: [Entry] = []

    var front: ChatApproval? { entries.first?.approval }
    var isEmpty: Bool { entries.isEmpty }

    mutating func push(_ approval: ChatApproval, token: Token) { entries.append(Entry(approval: approval, token: token)) }

    /// The first request, answered or given up on.
    mutating func popFront() -> Entry? { entries.isEmpty ? nil : entries.removeFirst() }

    /// One request by id (its connection closed, or it timed out).
    mutating func remove(id: UUID) -> Entry? {
        guard let i = entries.firstIndex(where: { $0.approval.id == id }) else { return nil }
        return entries.remove(at: i)
    }

    /// Every request of one chat session, or all of them (`nil`): Stop, a new conversation, a level change.
    mutating func removeAll(session: String? = nil) -> [Entry] {
        let gone = entries.filter { session == nil || $0.approval.sessionID == session }
        entries.removeAll { session == nil || $0.approval.sessionID == session }
        return gone
    }
}

extension ClaudeAgentReadiness {
    /// Whether Claude Code's settings carry a NotchMeow `PermissionRequest` hook (what `HookServer` installs).
    static func hooksInstalled(in settings: [String: Any]) -> Bool {
        guard let groups = (settings["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]] else { return false }
        return groups.contains { group in
            (group["hooks"] as? [[String: Any]] ?? []).contains {
                let command = $0["command"] as? String ?? ""
                return command.contains("nm-hook") || command.contains("NotchMeow") || command.contains("notchmeow")
            }
        }
    }
}

#endif
