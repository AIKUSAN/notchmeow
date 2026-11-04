import Foundation

// Which hook payloads belong to a chat. `PermissionRequest` carries the `session_id` Claude Code was started with;
// NotchMeow chose that id (`--session-id`), so a match is a chat's own run. Everything else is handled as before:
// the user's own sessions keep reaching their own pills and cards. No `nm_*` field is involved.
// Rules: `tests/fixtures/ai/claude-code/hook-routing.json`.

#if !APPSTORE

enum ClaudeHookRouting {
    enum Route: Equatable {
        case chat(sessionID: String)
        case other
    }

    /// `live`: the ids of the chats that are open. Only an exact match of a string `session_id` counts, and a payload
    /// from another agent (`nm_agent`) never does.
    static func route(payload: [String: Any], live: Set<String>) -> Route {
        if let agent = payload["nm_agent"] as? String, !agent.isEmpty { return .other }
        guard let id = payload["session_id"] as? String, !id.isEmpty, live.contains(id) else { return .other }
        return .chat(sessionID: id)
    }
}

#endif
