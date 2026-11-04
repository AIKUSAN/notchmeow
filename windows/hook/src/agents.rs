//! Gemini CLI and Antigravity (`agy`) speak their own dialect of hook JSON. This
//! file turns it into the Claude-like shapes the island already handles, the way
//! the macOS relay does (`nm-hook`, embedded in HookServer.swift): the same event
//! table, the same field mapping, the same `{}` answer (Antigravity's PreToolUse gets
//! `{"decision":"ask"}`, see `silent_answer`).
//!
//! Pure functions, no I/O, so the tests run on every OS. Claude Code events pass
//! through untouched: no Claude Code event name is in the table, and the field
//! mapping does nothing for a payload that already carries `tool_name`.

use serde_json::{Map, Value};

/// The `--agent` values of the two agents. They become `nm_agent`, which the island
/// routes on, so the pills are `agent_gemini` and `agent_antigravity`, as on the Mac.
pub const GEMINI: &str = "gemini";
pub const ANTIGRAVITY: &str = "antigravity";
/// A Claude Code session started from the Claude desktop app: it says so in `CLAUDE_CODE_ENTRYPOINT` and runs in no terminal. The tag says where it runs; the session is Claude Code's, under the Claude Code pill, and its host is the Claude app.
pub const CLAUDE_DESKTOP: &str = "claude-desktop";

/// The `nm_agent` tag of an event: `--agent` when given, otherwise `claude-desktop` for a session whose entrypoint says so, otherwise none (Claude Code).
pub fn agent_tag(arg: &str, entrypoint: &str) -> String {
    if !arg.is_empty() {
        arg.to_string()
    } else if entrypoint == CLAUDE_DESKTOP {
        CLAUDE_DESKTOP.to_string()
    } else {
        String::new()
    }
}

/// Gemini CLI and Antigravity event names to the names the island handles.
/// Anything else, Claude Code's names included, comes back unchanged.
pub fn normalize_event(name: &str) -> &str {
    match name {
        "BeforeTool" | "BeforeToolSelection" => "PreToolUse",
        "AfterTool" | "AfterModel" => "PostToolUse",
        "BeforeAgent" => "UserPromptSubmit",
        "AfterAgent" => "Stop",
        "startup" => "SessionStart",
        "exit" => "SessionEnd",
        "PreInvocation" => "UserPromptSubmit",
        "PostInvocation" => "PostToolUse",
        other => other,
    }
}

/// Antigravity's PascalCase tool arguments and the keys the island reads.
const ARG_ALIASES: [(&str, &str); 6] = [
    ("CommandLine", "command"),
    ("FilePath", "file_path"),
    ("Path", "path"),
    ("Url", "url"),
    ("Query", "query"),
    ("Pattern", "pattern"),
];

/// Where Antigravity and Gemini CLI may keep the session id.
const SESSION_KEYS: [&str; 4] = ["conversationId", "conversation_id", "sessionId", "GEMINI_SESSION_ID"];

/// Antigravity wraps a tool call as `toolCall: {name, args}` and names the session
/// `conversationId`. Maps both onto `tool_name`, `tool_input` and `session_id`.
/// Fields already there win, and a payload that already has `tool_name` (Claude
/// Code, Gemini CLI's tool events) is left exactly as it is. `env_session_id` is
/// the value of `GEMINI_SESSION_ID`, the last place to look.
pub fn normalize_tool_fields(map: &mut Map<String, Value>, env_session_id: &str) {
    if map.contains_key("tool_name") {
        return;
    }
    let tool = map.get("toolCall").cloned().unwrap_or(Value::Null);
    let name = tool
        .get("name")
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty())
        .or_else(|| map.get("tool").and_then(Value::as_str).filter(|s| !s.is_empty()))
        .map(str::to_string);
    if let Some(name) = name {
        map.insert("tool_name".into(), Value::String(name));
    }
    if !map.contains_key("tool_input") {
        if let Some(args) = tool.get("args").and_then(Value::as_object) {
            let mut flat = args.clone();
            for (from, to) in ARG_ALIASES {
                if let Some(value) = args.get(from) {
                    flat.insert(to.into(), value.clone());
                }
            }
            map.insert("tool_input".into(), Value::Object(flat));
        }
    }
    if !map.contains_key("session_id") {
        let id = SESSION_KEYS
            .iter()
            .find_map(|key| map.get(*key).and_then(Value::as_str).filter(|s| !s.is_empty()))
            .or_else(|| Some(env_session_id).filter(|s| !s.is_empty()))
            .map(str::to_string);
        if let Some(id) = id {
            map.insert("session_id".into(), Value::String(id));
        }
    }
}

/// Antigravity reports the folder it works in as `workspacePaths[0]`, and some
/// agents as `workspace_roots[0]`. Used when the payload has no `cwd`.
pub fn workspace_cwd(map: &Map<String, Value>) -> Option<String> {
    ["workspacePaths", "workspace_roots"]
        .iter()
        .filter_map(|key| map.get(*key).and_then(Value::as_array))
        .find(|paths| !paths.is_empty())
        .and_then(|paths| paths[0].as_str())
        .filter(|s| !s.is_empty())
        .map(str::to_string)
}

/// Gemini CLI and Antigravity read a hook's stdout as JSON, and `{}` is their
/// "no decision". Claude Code and every other agent want silence. `event` is the
/// translated event name. Antigravity reads `{}` on PreToolUse as a denial, so it is
/// answered "ask": its own permission prompt (and the user's Always Allow) stays, and
/// NotchMeow never allows a tool by itself.
pub fn silent_answer(agent: &str, event: &str) -> Option<&'static str> {
    if agent == ANTIGRAVITY && event == "PreToolUse" {
        return Some(r#"{"decision":"ask"}"#);
    }
    matches!(agent, GEMINI | ANTIGRAVITY).then_some("{}")
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn obj(v: Value) -> Map<String, Value> {
        v.as_object().cloned().expect("a JSON object")
    }

    #[test]
    fn gemini_and_antigravity_event_names_become_the_islands() {
        for (from, to) in [
            ("BeforeTool", "PreToolUse"),
            ("BeforeToolSelection", "PreToolUse"),
            ("AfterTool", "PostToolUse"),
            ("AfterModel", "PostToolUse"),
            ("BeforeAgent", "UserPromptSubmit"),
            ("AfterAgent", "Stop"),
            ("startup", "SessionStart"),
            ("exit", "SessionEnd"),
            ("PreInvocation", "UserPromptSubmit"),
            ("PostInvocation", "PostToolUse"),
        ] {
            assert_eq!(normalize_event(from), to, "{from}");
        }
    }

    #[test]
    fn claude_code_event_names_pass_through_unchanged() {
        for name in [
            "SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse",
            "PostToolUseFailure", "PermissionRequest", "Notification", "Stop", "StopFailure",
            "SubagentStart", "SubagentStop", "", "SomethingNew",
        ] {
            assert_eq!(normalize_event(name), name);
        }
    }

    #[test]
    fn an_antigravity_tool_call_becomes_tool_name_tool_input_and_session_id() {
        let mut map = obj(json!({
            "toolCall": { "name": "example_tool", "args": { "CommandLine": "ls -la", "Cwd": "/work" } },
            "conversationId": "conv-1"
        }));
        normalize_tool_fields(&mut map, "");
        assert_eq!(map["tool_name"], "example_tool");
        // The raw keys stay next to the flat ones the island reads.
        assert_eq!(map["tool_input"], json!({ "CommandLine": "ls -la", "command": "ls -la", "Cwd": "/work" }));
        assert_eq!(map["session_id"], "conv-1");
    }

    #[test]
    fn every_pascal_case_argument_gets_its_flat_twin() {
        let mut map = obj(json!({ "toolCall": { "name": "t", "args": {
            "CommandLine": "a", "FilePath": "b", "Path": "c", "Url": "d", "Query": "e", "Pattern": "f"
        } } }));
        normalize_tool_fields(&mut map, "");
        let input = &map["tool_input"];
        for (flat, want) in [("command", "a"), ("file_path", "b"), ("path", "c"), ("url", "d"), ("query", "e"), ("pattern", "f")] {
            assert_eq!(input[flat], want, "{flat}");
        }
    }

    #[test]
    fn a_payload_that_already_has_tool_name_is_left_exactly_as_it_is() {
        // Claude Code and Gemini CLI's tool events: nothing is added, not even a
        // session id from the environment (the macOS relay behaves the same).
        let before = obj(json!({
            "tool_name": "Bash", "tool_input": { "command": "ls" },
            "toolCall": { "name": "other", "args": { "CommandLine": "x" } },
            "conversationId": "conv-1"
        }));
        let mut after = before.clone();
        normalize_tool_fields(&mut after, "from-env");
        assert_eq!(after, before);
    }

    #[test]
    fn a_plain_tool_string_is_used_when_there_is_no_tool_call() {
        let mut map = obj(json!({ "tool": "read_file" }));
        normalize_tool_fields(&mut map, "");
        assert_eq!(map["tool_name"], "read_file");
        assert!(!map.contains_key("tool_input"));
    }

    #[test]
    fn existing_tool_input_and_session_id_win() {
        let mut map = obj(json!({
            "toolCall": { "name": "t", "args": { "CommandLine": "from-args" } },
            "tool_input": { "command": "kept" },
            "session_id": "kept-id",
            "conversationId": "conv-1"
        }));
        normalize_tool_fields(&mut map, "from-env");
        assert_eq!(map["tool_input"], json!({ "command": "kept" }));
        assert_eq!(map["session_id"], "kept-id");
        assert_eq!(map["tool_name"], "t");
    }

    #[test]
    fn odd_shapes_are_ignored_never_a_panic() {
        for payload in [
            json!({ "toolCall": "not an object" }),
            json!({ "toolCall": { "name": 7, "args": "nope" } }),
            json!({ "toolCall": { "name": "", "args": [1, 2] }, "tool": "" }),
            json!({ "toolCall": null, "conversationId": 5 }),
            json!({}),
        ] {
            let mut map = obj(payload.clone());
            normalize_tool_fields(&mut map, "");
            assert!(!map.contains_key("tool_name"), "{payload}");
            assert!(!map.contains_key("tool_input"), "{payload}");
            assert!(!map.contains_key("session_id"), "{payload}");
        }
    }

    #[test]
    fn the_session_id_comes_from_the_first_key_that_has_one_then_the_environment() {
        let mut map = obj(json!({ "conversationId": "", "conversation_id": "c-2", "sessionId": "s-3" }));
        normalize_tool_fields(&mut map, "env-4");
        assert_eq!(map["session_id"], "c-2");

        let mut map = obj(json!({}));
        normalize_tool_fields(&mut map, "env-4");
        assert_eq!(map["session_id"], "env-4");

        let mut map = obj(json!({}));
        normalize_tool_fields(&mut map, "");
        assert!(!map.contains_key("session_id"));
    }

    #[test]
    fn the_workspace_folder_is_the_first_path_of_the_first_list_that_has_one() {
        assert_eq!(workspace_cwd(&obj(json!({ "workspacePaths": ["/a", "/b"] }))).as_deref(), Some("/a"));
        assert_eq!(
            workspace_cwd(&obj(json!({ "workspacePaths": [], "workspace_roots": ["/r"] }))).as_deref(),
            Some("/r")
        );
        for none in [
            json!({}),
            json!({ "workspacePaths": [] }),
            json!({ "workspacePaths": [7] }),
            json!({ "workspacePaths": [""] }),
            json!({ "workspacePaths": "/a" }),
        ] {
            assert_eq!(workspace_cwd(&obj(none.clone())), None, "{none}");
        }
    }

    #[test]
    fn only_gemini_and_antigravity_get_the_empty_json_answer() {
        assert_eq!(silent_answer("gemini", "PreToolUse"), Some("{}"));
        assert_eq!(silent_answer("antigravity", "PostToolUse"), Some("{}"));
        for other in ["", "claude", "codex", "cursor", "my-tool", "Gemini", "gemini-cli"] {
            assert_eq!(silent_answer(other, "PreToolUse"), None, "{other}");
        }
    }

    #[test]
    fn a_claude_desktop_session_is_tagged_and_an_explicit_agent_wins() {
        assert_eq!(agent_tag("", "claude-desktop"), "claude-desktop");
        assert_eq!(agent_tag("gemini", "claude-desktop"), "gemini");
        for other in ["", "cli", "vscode", "Claude-Desktop", "claude-desktop "] {
            assert_eq!(agent_tag("", other), "", "{other:?}");
        }
        assert_eq!(agent_tag("antigravity", ""), "antigravity");
        // Claude Desktop answers like any other tagged agent: no JSON is forced on it.
        assert_eq!(silent_answer(CLAUDE_DESKTOP, "PreToolUse"), None);
    }

    #[test]
    fn antigravity_pre_tool_use_is_asked_never_answered_empty_or_allowed() {
        assert_eq!(silent_answer("antigravity", "PreToolUse"), Some(r#"{"decision":"ask"}"#));
        for event in ["PostToolUse", "UserPromptSubmit", "Stop", "SessionStart", "PermissionRequest"] {
            assert_eq!(silent_answer("antigravity", event), Some("{}"), "{event}");
        }
        // Gemini keeps `{}` on every event, PreToolUse included.
        assert_eq!(silent_answer("gemini", "PreToolUse"), Some("{}"));
        // Whatever it answers, it never says allow.
        for event in ["PreToolUse", "PostToolUse", "Stop"] {
            assert!(!silent_answer("antigravity", event).unwrap().contains("allow"), "{event}");
        }
    }
}
