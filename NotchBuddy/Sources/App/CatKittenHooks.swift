import Foundation

// What a hook event does to the kittens: the one place that reads the hooks' words. `SubagentStart` adds a kitten, a `PreToolUse` or `PostToolUse` that carries an
// `agent_id` sets its state, a `PermissionRequest` that carries one makes it wait on an approval, `SubagentStop` makes it leave, and the parent's own Stop (or the session
// ending) takes all of them. An event without an `agent_id` is the parent's own and is not a kitten event: that is the fallback for a Claude Code that sends none (kittens still
// appear at the start and leave at the stop, in the working pose). The app (`HookServer`) calls this and hands the result to `CatKittens.step`. Foundation only.

enum CatKittenHooks {
    /// The subagent an event belongs to: its `agent_id` (text, 1 to 128 characters), or nil when the event is the parent's own.
    static func subagentId(_ payload: [String: Any]) -> String? {
        (payload["agent_id"] as? String).flatMap { CatKittens.isKittenId($0) ? $0 : nil }
    }

    /// The session an event belongs to, as the hook server reads it (`session_id`, else `conversation_id`), or nil when it has none.
    static func sessionId(_ payload: [String: Any]) -> String? {
        ["session_id", "conversation_id"].compactMap { payload[$0] as? String }.first { CatKittens.isKittenId($0) }
    }

    /// The kitten event a hook event carries at `now` (ms on the app's clock), or nil when it carries none. `PermissionRequest` is `permission(payload:now:)`, because the
    /// hook server handles it apart.
    static func event(name: String, payload: [String: Any], now: Double) -> CatKittens.Event? {
        switch name {
        case "SubagentStart":
            return subagentId(payload).map { .start(id: $0, agentType: payload["agent_type"] as? String, session: sessionId(payload), t: now) }
        case "SubagentStop":
            return subagentId(payload).map { .stop(id: $0, t: now) }
        case "PreToolUse", "PostToolUse":
            return subagentId(payload).map { .tool(id: $0, tool: payload["tool_name"] as? String, t: now) }
        case "Stop", "StopFailure", "SessionEnd", "Interrupt":
            // the parent's turn or session is over: no kittens (those of its other sessions stay). A Stop that names a subagent is not the parent's.
            return subagentId(payload) == nil ? .end(session: sessionId(payload), t: now) : nil
        default:
            return nil
        }
    }

    /// A permission request from a subagent: its kitten waits on an approval.
    static func permission(payload: [String: Any], now: Double) -> CatKittens.Event? {
        subagentId(payload).map { .permission(id: $0, t: now) }
    }

    /// The request was answered, or dismissed, or displaced by the next one: the kitten is back to work.
    static func resolved(subagentId id: String, now: Double) -> CatKittens.Event { .resolved(id: id, t: now) }
}
