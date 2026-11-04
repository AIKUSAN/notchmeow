// Claude Code as an engine, the pure parts: the levels, the command line of one turn, the environment it runs in, the
// message written to its stdin, what its stream-json output means, and the words of each failure. Nothing here starts a
// process (`claude_run.rs` does). It mirrors NotchBuddy/Sources/App/AI/Core/ClaudeCode*.swift: both apps are held to
// tests/fixtures/ai/claude-code/, and `reference.py` there is the tie-breaker.
//
// The exact JSON of Claude Code's failures is not documented, so the parser is tolerant on purpose: a line that is not
// JSON, or an event it does not know, is skipped; a run that ends without a result and without a failure it recognises
// is "Claude stopped unexpectedly", never a guess at what went wrong.

use std::collections::BTreeMap;

use serde_json::{json, Value};

use crate::ai::errors::{Action, Wording};
use crate::ai::provider::{file_text, AiError, ChatChunk, EngineReport, ErrorKind, Finish, Part, Payer, Step, StepState};

/// Claude Code's own model aliases (its `--model` values).
pub const MODELS: [&str; 3] = ["sonnet", "opus", "haiku"];

/// A model alias from settings: itself when it is one of Claude Code's, else the default.
pub fn model_or_default(alias: &str) -> String {
    if MODELS.contains(&alias) { alias } else { MODELS[0] }.to_string()
}

/// The codes on `AiError::code` for Claude Code's failures, on top of the twelve shared error kinds.
pub const MISSING: &str = "nm_claude_missing";
pub const SIGNED_OUT: &str = "nm_signed_out";
pub const PLAN_LIMIT: &str = "nm_plan_limit";
pub const TOO_OLD: &str = "nm_claude_old";
pub const CRASHED: &str = "nm_claude_crashed";
pub const OFFLINE: &str = "nm_claude_offline";
pub const NEEDS_GIT: &str = "nm_needs_git";
pub const FOLDER_MISSING: &str = "nm_folder_missing";
/// No tools: the run started with tools a quick action must not have, or showed one before its init, so NotchMeow stopped it.
pub const TOOLS_PRESENT: &str = "nm_tools_present";

/// The tools `init` must report, for a level that checks them: No tools reports none. `None`: no check (the other levels).
pub fn init_tools(level: &Level) -> Option<&'static [&'static str]> {
    match level {
        Level::NoTools => Some(&[]),
        _ => None,
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Platform {
    Mac,
    Linux,
    Windows,
}

impl Platform {
    pub fn current() -> Self {
        if cfg!(windows) {
            Platform::Windows
        } else if cfg!(target_os = "macos") {
            Platform::Mac
        } else {
            Platform::Linux
        }
    }
}

/// What Claude may do in a chat. Read-only and Agent carry the folder the user chose. No tools (quick actions only) has no
/// folder: it runs in the chat folder.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Level {
    ChatOnly,
    ReadOnly(String),
    Agent(String),
    NoTools,
}

impl Level {
    /// `chat`, `read`, `agent` or `none`, as in the fixtures.
    pub fn key(&self) -> &'static str {
        match self {
            Level::ChatOnly => "chat",
            Level::ReadOnly(_) => "read",
            Level::Agent(_) => "agent",
            Level::NoTools => "none",
        }
    }

    pub fn folder(&self) -> Option<&str> {
        match self {
            Level::ChatOnly | Level::NoTools => None,
            Level::ReadOnly(f) | Level::Agent(f) => Some(f),
        }
    }
}

/// One run of Claude Code: everything except the message itself.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Turn {
    pub level: Level,
    pub model: String,
    /// The id NotchMeow chose for this chat's Claude Code session (lower-case UUID).
    pub session_id: String,
    /// False on a chat's first turn (`--session-id`), true on the later ones (`--resume`).
    pub resume: bool,
    pub platform: Platform,
}

const BASE: [&str; 7] =
    ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages"];
const CHAT_TOOLS: &str = "WebSearch,WebFetch";
const NONE_DENY: &str = "WebSearch,WebFetch,mcp__*";
const READ_TOOLS: &str = "Read,Grep,Glob,WebSearch,WebFetch";
const READ_SETTINGS: &str = r#"{"permissions":{"blockReadsOutsideWorkingDirectories":true}}"#;
const SANDBOX_SETTINGS: &str = r#"{"sandbox":{"enabled":true,"allowUnsandboxedCommands":false,"autoAllowBashIfSandboxed":false}}"#;

/// The arguments after the program name. Every quoted value of the spec is one element: there is no shell. The folder is
/// the process's working folder, never an argument.
pub fn arguments(turn: &Turn) -> Vec<String> {
    let mut args: Vec<String> = BASE.iter().map(|s| s.to_string()).collect();
    args.extend([
        if turn.resume { "--resume" } else { "--session-id" }.to_string(),
        turn.session_id.clone(),
        "--model".to_string(),
        turn.model.clone(),
    ]);
    let more: &[&str] = match &turn.level {
        Level::ChatOnly => &[
            "--safe-mode", "--tools", CHAT_TOOLS, "--allowedTools", CHAT_TOOLS, "--disallowedTools", "mcp__*",
            "--permission-mode", "dontAsk",
        ],
        // No tools: an empty --tools list, nothing allowed, every MCP server blocked.
        Level::NoTools => &["--safe-mode", "--tools", "", "--disallowedTools", NONE_DENY, "--permission-mode", "dontAsk"],
        Level::ReadOnly(_) => &[
            "--safe-mode", "--tools", READ_TOOLS, "--allowedTools", READ_TOOLS, "--permission-mode", "dontAsk",
            "--settings", READ_SETTINGS,
        ],
        // Native Windows has no command sandbox: there every command asks.
        Level::Agent(_) if turn.platform == Platform::Windows => &["--permission-mode", "default"],
        Level::Agent(_) => &["--permission-mode", "default", "--settings", SANDBOX_SETTINGS],
    };
    args.extend(more.iter().map(|s| s.to_string()));
    args
}

/// The folder the process runs in: the user's for Read-only and Agent, NotchMeow's own empty one for Chat only.
pub fn working_directory(turn: &Turn, chat_folder: &str) -> String {
    turn.level.folder().unwrap_or(chat_folder).to_string()
}

/// Variables that outrank the user's plan login in Claude Code's own order of precedence.
pub const STRIPPED: [&str; 4] = ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_PROFILE"];
pub const STRIPPED_PREFIXES: [&str; 1] = ["CLAUDE_CODE_USE_"];

/// The environment of a run: the caller's, without what would outrank the plan login. On Windows names compare without
/// regard to case. An `apiKeyHelper` is a setting, not a variable: it is not touched.
pub fn environment(base: impl IntoIterator<Item = (String, String)>, platform: Platform) -> Vec<(String, String)> {
    let insensitive = platform == Platform::Windows;
    base.into_iter()
        .filter(|(name, _)| {
            let key = if insensitive { name.to_uppercase() } else { name.clone() };
            !STRIPPED.contains(&key.as_str()) && !STRIPPED_PREFIXES.iter().any(|p| key.starts_with(p))
        })
        .collect()
}

fn block(part: &Part) -> Value {
    match part {
        Part::Text(t) => json!({ "type": "text", "text": t }),
        Part::FileText { name, text } => json!({ "type": "text", "text": file_text(name, text) }),
        Part::Image { mime, base64, .. } => {
            json!({ "type": "image", "source": { "type": "base64", "media_type": mime, "data": base64 } })
        }
        Part::Pdf { base64, .. } => {
            json!({ "type": "document", "source": { "type": "base64", "media_type": "application/pdf", "data": base64 } })
        }
    }
}

/// The one line written to stdin: the new message as content blocks (a dropped image or PDF as a block, other files as
/// text), in the documented user-message shape. `preamble` is a recap of the chat so far, only for a session that is
/// started afresh in the middle of a chat.
pub fn user_line(parts: &[Part], preamble: Option<&str>) -> String {
    let mut content = Vec::new();
    if let Some(recap) = preamble.filter(|p| !p.is_empty()) {
        content.push(json!({ "type": "text", "text": recap }));
    }
    content.extend(parts.iter().map(block));
    let mut line = json!({
        "type": "user",
        "message": { "role": "user", "content": content },
        "parent_tool_use_id": Value::Null,
    })
    .to_string();
    line.push('\n');
    line
}

// ── What the stream means ───────────────────────────────────────────────────────────────────────────────────────────

const STEP_FIELDS: [&str; 6] = ["command", "file_path", "path", "query", "pattern", "url"];
const STEP_FIELD_CAP: usize = 200;

fn payer(source: Option<&str>) -> Payer {
    match source {
        Some("none") | Some("oauth") => Payer::Plan,
        Some("user") | Some("project") | Some("org") | Some("temporary") => Payer::ApiKey,
        _ => Payer::Unknown,
    }
}

fn step_input(raw: &Value) -> BTreeMap<String, String> {
    STEP_FIELDS
        .iter()
        .filter_map(|k| raw.get(*k).and_then(Value::as_str).map(|v| (k.to_string(), v.chars().take(STEP_FIELD_CAP).collect())))
        .collect()
}

/// An event that would put something on screen, or run a tool, before the tools are checked. `reference.py`'s `shows_something`.
fn shows_something(event: &Value) -> bool {
    match event.get("type").and_then(Value::as_str) {
        Some("stream_event") => matches!(
            event.pointer("/event/type").and_then(Value::as_str),
            Some("content_block_start" | "content_block_delta")
        ),
        Some("assistant") => has_block(event, "tool_use"),
        Some("user") => has_block(event, "tool_result"),
        _ => false,
    }
}

fn has_block(event: &Value, kind: &str) -> bool {
    event.pointer("/message/content").and_then(Value::as_array).is_some_and(|blocks| blocks.iter().any(|b| b.get("type").and_then(Value::as_str) == Some(kind)))
}

/// One run's output, read a line at a time.
#[derive(Debug, Default)]
pub struct Stream {
    engine: Option<EngineReport>,
    text: String,
    need_break: bool,
    steps: BTreeMap<String, Step>,
    finished: bool,
    result_seen: bool,
    result_text: String,
    assistant_error: Option<String>,
    /// None: no rate-limit event that rejected; Some(0): rejected, no time given; else Unix seconds.
    rejected_resets_at: Option<u64>,
    retried: bool,
    /// The tools `init` must report, for a level that checks them; None: no check (`init_tools`).
    expected_tools: Option<&'static [&'static str]>,
    /// True once a passing `init` was seen; the check is then done.
    tools_vetted: bool,
    /// True once the run showed tools its level must not have. Every later line is ignored; stopping the process is the run's job.
    refused: bool,
}

impl Stream {
    pub fn new() -> Self {
        Stream::default()
    }

    /// A stream that checks its `init`'s tools against `expected` (see `init_tools`). `None` checks nothing, as `new` does.
    pub fn with_init_tools(expected: Option<&'static [&'static str]>) -> Self {
        Stream { expected_tools: expected, ..Stream::default() }
    }

    /// Whether the run showed tools its level must not have. Such a run is stopped and reported as `nm_tools_present`.
    pub fn refused_tools(&self) -> bool {
        self.refused
    }

    /// Everything shown so far.
    pub fn text(&self) -> &str {
        &self.text
    }

    /// Whether Claude Code took at least one step.
    pub fn took_steps(&self) -> bool {
        !self.steps.is_empty()
    }

    /// Chunks for one line of stdout.
    pub fn consume(&mut self, line: &str) -> Vec<ChatChunk> {
        if self.refused {
            return Vec::new();
        }
        let Ok(event) = serde_json::from_str::<Value>(line) else { return Vec::new() };
        if self.expected_tools.is_some() && !self.tools_vetted && shows_something(&event) {
            self.refused = true;
            return Vec::new();
        }
        match event.get("type").and_then(Value::as_str) {
            Some("system") => match event.get("subtype").and_then(Value::as_str) {
                Some("init") => {
                    let report = EngineReport {
                        session_id: event.get("session_id").and_then(Value::as_str).unwrap_or("").to_string(),
                        model: event.get("model").and_then(Value::as_str).unwrap_or("").to_string(),
                        paid_by: payer(event.get("apiKeySource").and_then(Value::as_str)),
                        version: event.get("claude_code_version").and_then(Value::as_str).map(str::to_string),
                    };
                    self.engine = Some(report.clone());
                    if let (Some(expected), false) = (self.expected_tools, self.tools_vetted) {
                        // `tools` must be a list of strings equal to the expected one, in order. Anything else refuses.
                        let tools: Option<Vec<&str>> = event.get("tools").and_then(Value::as_array).and_then(|list| list.iter().map(Value::as_str).collect());
                        if tools.is_some_and(|names| names.into_iter().eq(expected.iter().copied())) {
                            self.tools_vetted = true;
                        } else {
                            self.refused = true;
                        }
                    }
                    vec![ChatChunk::Engine(report)]
                }
                Some("api_retry") => {
                    self.retried = true;
                    Vec::new()
                }
                _ => Vec::new(),
            },
            Some("stream_event") => self.stream_event(event.get("event").unwrap_or(&Value::Null)),
            Some("assistant") => self.assistant(&event),
            Some("user") => self.tool_results(&event),
            Some("rate_limit_event") => {
                let info = event.get("rate_limit_info").unwrap_or(&Value::Null);
                if info.get("status").and_then(Value::as_str) == Some("rejected") {
                    // As Swift (`int64Value`) and the reference (`int()`) read it: a float is cut, a negative or unreadable time is 0.
                    let at = info.get("resetsAt").and_then(|v| v.as_u64().or_else(|| v.as_f64().filter(|f| f.is_finite() && *f > 0.0).map(|f| f as u64)));
                    self.rejected_resets_at = Some(at.unwrap_or(0));
                }
                Vec::new()
            }
            Some("result") => {
                self.result_seen = true;
                let is_error = event.get("is_error").and_then(Value::as_bool).unwrap_or(false);
                let subtype = event.get("subtype").and_then(Value::as_str).unwrap_or("");
                self.result_text = event.get("result").and_then(Value::as_str).unwrap_or("").to_string();
                if !is_error && subtype == "success" {
                    self.finished = true;
                    return vec![ChatChunk::Finish(Finish::Stop)];
                }
                if subtype == "error_max_turns" {
                    self.finished = true;
                    return vec![ChatChunk::Finish(Finish::Length)];
                }
                Vec::new()
            }
            _ => Vec::new(),
        }
    }

    fn stream_event(&mut self, e: &Value) -> Vec<ChatChunk> {
        match e.get("type").and_then(Value::as_str) {
            Some("message_start") => {
                self.need_break = self.need_break || !self.text.is_empty();
                Vec::new()
            }
            Some("content_block_start") => {
                let block = e.get("content_block").unwrap_or(&Value::Null);
                let kind = block.get("type").and_then(Value::as_str);
                if let (Some("tool_use"), Some(id)) = (kind, block.get("id").and_then(Value::as_str)) {
                    self.need_break = self.need_break || !self.text.is_empty();
                    let step = Step {
                        id: id.to_string(),
                        tool: block.get("name").and_then(Value::as_str).unwrap_or("").to_string(),
                        input: BTreeMap::new(),
                        state: StepState::Running,
                    };
                    self.steps.insert(id.to_string(), step.clone());
                    return vec![ChatChunk::Step(step)];
                }
                if kind == Some("text") && self.need_break && !self.text.is_empty() {
                    self.need_break = false;
                    self.text.push_str("\n\n");
                    return vec![ChatChunk::Text("\n\n".to_string())];
                }
                Vec::new()
            }
            Some("content_block_delta") => {
                let delta = e.get("delta").unwrap_or(&Value::Null);
                let (Some("text_delta"), Some(piece)) = (delta.get("type").and_then(Value::as_str), delta.get("text").and_then(Value::as_str))
                else {
                    return Vec::new();
                };
                let mut out = Vec::new();
                if self.need_break && !self.text.is_empty() {
                    self.text.push_str("\n\n");
                    out.push(ChatChunk::Text("\n\n".to_string()));
                }
                self.need_break = false;
                self.text.push_str(piece);
                out.push(ChatChunk::Text(piece.to_string()));
                out
            }
            _ => Vec::new(),
        }
    }

    fn assistant(&mut self, event: &Value) -> Vec<ChatChunk> {
        if let Some(error) = event.get("error").and_then(Value::as_str) {
            self.assistant_error = Some(error.to_string());
        }
        let mut out = Vec::new();
        let content = event.pointer("/message/content").and_then(Value::as_array).cloned().unwrap_or_default();
        for block in content.iter().filter(|b| b.get("type").and_then(Value::as_str) == Some("tool_use")) {
            let Some(id) = block.get("id").and_then(Value::as_str) else { continue };
            let Some(step) = self.steps.get_mut(id) else { continue };
            step.input = step_input(block.get("input").unwrap_or(&Value::Null));
            out.push(ChatChunk::Step(step.clone()));
        }
        out
    }

    fn tool_results(&mut self, event: &Value) -> Vec<ChatChunk> {
        let mut out = Vec::new();
        let content = event.pointer("/message/content").and_then(Value::as_array).cloned().unwrap_or_default();
        for block in content.iter().filter(|b| b.get("type").and_then(Value::as_str) == Some("tool_result")) {
            let Some(id) = block.get("tool_use_id").and_then(Value::as_str) else { continue };
            let Some(step) = self.steps.get_mut(id) else { continue };
            step.state = if block.get("is_error").and_then(Value::as_bool).unwrap_or(false) { StepState::Failed } else { StepState::Done };
            out.push(ChatChunk::Step(step.clone()));
        }
        out
    }

    /// `None` when the run ended well. Call once, after the process has exited. `stderr` is only read, never kept. The
    /// exit status is not used: Claude Code does not document one, and a result decides when there is one.
    pub fn failure(&self, stderr: &str) -> Option<AiError> {
        if self.refused {
            return Some(AiError { code: Some(TOOLS_PRESENT.to_string()), ..AiError::new(ErrorKind::BadRequest) });
        }
        if self.finished {
            return None;
        }
        let words = if self.result_seen { self.result_text.as_str() } else { "" };
        let blob = format!("{words}\n{stderr}").to_lowercase();
        let paid = self.engine.as_ref().map(|e| e.paid_by);
        let fail = |kind: ErrorKind, code: Option<&str>, resets_at: Option<u64>| {
            Some(AiError { code: code.map(str::to_string), resets_at: resets_at.filter(|t| *t > 0), ..AiError::new(kind) })
        };
        let assistant = self.assistant_error.as_deref();
        if blob.contains("git-bash") || blob.contains("claude_code_git_bash_path") || blob.contains("git for windows") {
            return fail(ErrorKind::BadRequest, Some(NEEDS_GIT), None);
        }
        if assistant == Some("authentication_failed") || blob.contains("not logged in") || blob.contains("please run /login") {
            return fail(ErrorKind::Auth, Some(SIGNED_OUT), None);
        }
        if blob.contains("unknown option") {
            return fail(ErrorKind::BadRequest, Some(TOO_OLD), None);
        }
        if self.rejected_resets_at.is_some() || (assistant == Some("rate_limit") && paid == Some(Payer::Plan)) {
            return fail(ErrorKind::Billing, Some(PLAN_LIMIT), self.rejected_resets_at);
        }
        match assistant {
            Some("rate_limit") => return fail(ErrorKind::RateLimited, None, None),
            Some("billing_error") => return fail(ErrorKind::Billing, Some("billing_error"), None),
            Some("overloaded") => return fail(ErrorKind::Overloaded, None, None),
            Some("server_error") => return fail(ErrorKind::Server, None, None),
            _ => {}
        }
        if self.result_seen && (self.retried || blob.contains("unable to connect")) {
            return fail(ErrorKind::Unreachable, Some(OFFLINE), None);
        }
        fail(ErrorKind::Interrupted, Some(CRASHED), None)
    }
}

// ── The words ───────────────────────────────────────────────────────────────────────────────────────────────────────

/// The note for one of Claude Code's failures, or `None` for any other error (the general words then decide). The time of
/// a plan limit is not formatted here: the webview does it in the viewer's time zone and locale, from `resets_at`.
pub fn wording(err: &AiError) -> Option<Wording> {
    let (text, action) = match err.code.as_deref()? {
        MISSING => ("Claude Code isn't installed.", Some(Action::InstallClaude)),
        SIGNED_OUT => ("Claude Code is signed out.", Some(Action::SignInClaude)),
        PLAN_LIMIT => ("Your Claude plan's limit was reached.", None),
        TOO_OLD => ("Update Claude Code.", Some(Action::UpdateClaude)),
        CRASHED => ("Claude stopped unexpectedly.", Some(Action::TryAgain)),
        OFFLINE => ("Couldn't reach Claude.", None),
        NEEDS_GIT => ("Claude Code needs Git for Windows.", Some(Action::InstallGit)),
        FOLDER_MISSING => ("That folder isn't there any more. Pick another one.", None),
        TOOLS_PRESENT => ("Claude Code started with tools a quick action must not have, so NotchMeow stopped it.", None),
        _ => return None,
    };
    Some(Wording { text: text.to_string(), action })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ai::testkit;

    fn level(key: &str, folder: Option<&str>) -> Level {
        match key {
            "none" => Level::NoTools,
            "read" => Level::ReadOnly(folder.unwrap_or("").to_string()),
            "agent" => Level::Agent(folder.unwrap_or("").to_string()),
            _ => Level::ChatOnly,
        }
    }

    fn platform(name: &str) -> Platform {
        match name {
            "windows" => Platform::Windows,
            "linux" => Platform::Linux,
            _ => Platform::Mac,
        }
    }

    #[test]
    fn the_command_line_of_every_level_and_turn() {
        let data = testkit::load_json("claude-code/expected-args.json");
        let chat_folder = data["chatFolder"].as_str().unwrap();
        assert_eq!(MODELS.to_vec(), data["models"].as_array().unwrap().iter().map(|m| m.as_str().unwrap()).collect::<Vec<_>>());
        for c in data["cases"].as_array().unwrap() {
            let name = c["name"].as_str().unwrap();
            let turn = Turn {
                level: level(c["level"].as_str().unwrap(), c["folder"].as_str()),
                model: c["model"].as_str().unwrap().to_string(),
                session_id: c["sessionId"].as_str().unwrap().to_string(),
                resume: c["resume"].as_bool().unwrap(),
                platform: platform(c["platform"].as_str().unwrap()),
            };
            let argv = arguments(&turn);
            let want: Vec<String> = c["argv"].as_array().unwrap().iter().map(|a| a.as_str().unwrap().to_string()).collect();
            assert_eq!(argv, want, "{name}");
            let cwd = working_directory(&turn, chat_folder);
            let expected = if c["cwd"] == "chatFolder" { chat_folder } else { c["folder"].as_str().unwrap() };
            assert_eq!(cwd, expected, "{name}: runs in");
            if let Some(folder) = c["folder"].as_str() {
                assert!(!argv.iter().any(|a| a.contains(folder)), "{name}: the folder is an argument");
            }
            assert!(!argv.iter().any(|a| a == "--bare"), "{name}: --bare breaks subscription auth");
        }
    }

    #[test]
    fn the_environment_of_a_run() {
        let data = testkit::load_json("claude-code/expected-env.json");
        let names: Vec<&str> = data["stripped"].as_array().unwrap().iter().map(|n| n.as_str().unwrap()).collect();
        assert_eq!(STRIPPED.to_vec(), names);
        assert_eq!(STRIPPED_PREFIXES.to_vec(), vec![data["strippedPrefixes"][0].as_str().unwrap()]);
        for c in data["cases"].as_array().unwrap() {
            let pairs = |v: &Value| -> BTreeMap<String, String> {
                v.as_object().unwrap().iter().map(|(k, v)| (k.clone(), v.as_str().unwrap().to_string())).collect()
            };
            let got: BTreeMap<String, String> = environment(pairs(&c["base"]), platform(c["platform"].as_str().unwrap())).into_iter().collect();
            assert_eq!(got, pairs(&c["expect"]), "{}", c["name"]);
        }
    }

    #[test]
    fn a_model_alias_from_settings_is_one_of_claude_codes() {
        assert_eq!((model_or_default("opus"), model_or_default("gpt-6"), model_or_default("")), ("opus".to_string(), "sonnet".to_string(), "sonnet".to_string()));
    }

    #[test]
    fn the_message_on_stdin() {
        let line = user_line(
            &[
                Part::FileText { name: "notes.txt".into(), text: "hello".into() },
                Part::Image { name: "a.png".into(), mime: "image/png".into(), base64: "iVBO".into() },
                Part::Pdf { name: "a.pdf".into(), base64: "JVBE".into() },
                Part::Text("What is in these? Zoé 🐱".into()),
            ],
            None,
        );
        assert!(line.ends_with('\n') && !line[..line.len() - 1].contains('\n'), "one line");
        let json: Value = serde_json::from_str(&line).unwrap();
        assert_eq!((json["type"].as_str(), json["message"]["role"].as_str()), (Some("user"), Some("user")));
        assert!(json["parent_tool_use_id"].is_null());
        let blocks = json["message"]["content"].as_array().unwrap();
        let types: Vec<&str> = blocks.iter().map(|b| b["type"].as_str().unwrap()).collect();
        assert_eq!(types, ["text", "image", "document", "text"]);
        assert_eq!(blocks[0]["text"], "File: notes.txt\n\nhello");
        assert_eq!(blocks[3]["text"], "What is in these? Zoé 🐱");
        let recap: Value = serde_json::from_str(&user_line(&[Part::Text("and now?".into())], Some("Earlier in this chat: …"))).unwrap();
        let texts: Vec<&str> = recap["message"]["content"].as_array().unwrap().iter().map(|b| b["text"].as_str().unwrap()).collect();
        assert_eq!(texts, ["Earlier in this chat: …", "and now?"], "a recap comes first");
    }

    /// A whole run folded the way the chat sees it, at a level: a level that checks its tools checks its init.
    fn fold(level: &Level, lines: &str, stderr: &str) -> (Option<EngineReport>, String, Vec<Step>, Option<Finish>, Option<AiError>) {
        let mut stream = Stream::with_init_tools(init_tools(level));
        let (mut engine, mut text, mut steps, mut finish) = (None, String::new(), Vec::<Step>::new(), None);
        for line in lines.lines().filter(|l| !l.is_empty()) {
            for chunk in stream.consume(line) {
                match chunk {
                    ChatChunk::Engine(r) => engine = Some(r),
                    ChatChunk::Text(t) => text.push_str(&t),
                    ChatChunk::Finish(f) => finish = Some(f),
                    ChatChunk::Step(s) => match steps.iter_mut().find(|x| x.id == s.id) {
                        Some(old) => *old = s,
                        None => steps.push(s),
                    },
                    _ => {}
                }
            }
        }
        (engine, text, steps, finish, stream.failure(stderr))
    }

    #[test]
    fn what_a_transcript_means() {
        let data = testkit::load_json("claude-code/expected-parse.json");
        let sid = data["sessionId"].as_str().unwrap();
        for c in data["cases"].as_array().unwrap() {
            let name = c["name"].as_str().unwrap();
            let path = testkit::fixtures_dir().join("claude-code/transcripts").join(c["transcript"].as_str().unwrap());
            let raw = std::fs::read_to_string(path).unwrap().replace("__SESSION_ID__", sid).replace("__CWD__", data["cwd"].as_str().unwrap());
            let lvl = level(c.get("level").and_then(Value::as_str).unwrap_or("chat"), None);
            let (engine, text, steps, finish, error) = fold(&lvl, &raw, c["stderr"].as_str().unwrap());
            let expect = &c["expect"];
            match expect["engine"].as_object() {
                Some(e) => {
                    let got = engine.unwrap_or_else(|| panic!("{name}: no engine report"));
                    assert_eq!(
                        (got.session_id.as_str(), got.model.as_str(), serde_json::to_value(got.paid_by).unwrap(), got.version.as_deref()),
                        (sid, e["model"].as_str().unwrap(), e["paidBy"].clone(), e["version"].as_str()),
                        "{name}: engine"
                    );
                }
                None => assert!(engine.is_none(), "{name}: no engine report"),
            }
            assert_eq!(text, expect["text"].as_str().unwrap(), "{name}: text");
            let want_steps: Vec<(String, String, BTreeMap<String, String>, String)> = expect["steps"]
                .as_array()
                .unwrap()
                .iter()
                .map(|s| {
                    let input = s["input"].as_object().unwrap().iter().map(|(k, v)| (k.clone(), v.as_str().unwrap().to_string())).collect();
                    (s["id"].as_str().unwrap().into(), s["tool"].as_str().unwrap().into(), input, s["state"].as_str().unwrap().into())
                })
                .collect();
            let got_steps: Vec<_> =
                steps.iter().map(|s| (s.id.clone(), s.tool.clone(), s.input.clone(), serde_json::to_value(s.state).unwrap().as_str().unwrap().to_string())).collect();
            assert_eq!(got_steps, want_steps, "{name}: steps");
            assert_eq!(finish.map(|f| serde_json::to_value(f).unwrap()), expect["finish"].as_str().map(|f| json!(f)), "{name}: finish");
            match expect["error"].as_object() {
                Some(e) => {
                    let err = error.unwrap_or_else(|| panic!("{name}: no error"));
                    assert_eq!(serde_json::to_value(err.kind).unwrap(), e["kind"], "{name}: error kind");
                    assert_eq!(err.code.as_deref(), e["code"].as_str(), "{name}: error code");
                    assert_eq!(err.resets_at, e["resetsAt"].as_u64(), "{name}: resets at");
                }
                None => assert!(error.is_none(), "{name}: no error"),
            }
        }
    }

    /// Swift reads the time with `NSNumber.int64Value` and the reference with `int()`: a float is cut, a negative is none.
    #[test]
    fn a_reset_time_that_is_a_float_is_read_like_an_integer() {
        let resets = |value: &str| {
            let raw = format!("{{\"type\":\"rate_limit_event\",\"rate_limit_info\":{{\"status\":\"rejected\",\"resetsAt\":{value}}}}}\n{{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":true,\"result\":\"limit\"}}");
            let (.., error) = fold(&Level::ChatOnly, &raw, "");
            let error = error.unwrap();
            assert_eq!(error.code.as_deref(), Some(PLAN_LIMIT), "{value}: still the plan's limit");
            error.resets_at
        };
        assert_eq!(resets("1791301500"), Some(1_791_301_500));
        assert_eq!(resets("1791301500.0"), Some(1_791_301_500));
        assert_eq!(resets("1791301500.9"), Some(1_791_301_500), "cut, not rounded");
        assert_eq!(resets("-5"), None);
        assert_eq!(resets("-5.5"), None);
        assert_eq!(resets("0"), None);
        assert_eq!(resets("\"soon\""), None);
    }

    #[test]
    fn tolerance() {
        let (_, text, _, _, error) = fold(&Level::ChatOnly, "\nnot json\n[1,2]\n{\"type\":\"mystery\"}\n{\"type\":\"stream_event\"}\n{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"hi\"}}}", "");
        assert_eq!(text, "hi", "junk lines are skipped and the text survives");
        assert_eq!(error.unwrap().code.as_deref(), Some(CRASHED), "a run with no result is a crash");

        let (.., error) = fold(&Level::ChatOnly, "{\"type\":\"rate_limit_event\",\"rate_limit_info\":{\"status\":\"rejected\",\"resetsAt\":\"soon\"}}\n{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":true,\"result\":\"limit\"}", "");
        let error = error.unwrap();
        assert_eq!((error.code.as_deref(), error.resets_at), (Some(PLAN_LIMIT), None), "a rejection with a time we cannot read is still the plan's limit");

        let (.., error) = fold(&Level::ChatOnly, "{\"type\":\"rate_limit_event\",\"rate_limit_info\":{\"status\":\"allowed_warning\",\"resetsAt\":1791301500}}\n{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"result\":\"ok\"}", "");
        assert!(error.is_none(), "a warning is not a failure");

        let long = "é".repeat(300);
        let lines = format!(
            "{}\n{}\n{}",
            r#"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"t1","name":"Bash","input":{}}}}"#,
            json!({"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":long,"timeout":5000,"content":"secret"}}]}}),
            r#"{"type":"result","subtype":"success","is_error":false,"result":""}"#
        );
        let (_, _, steps, ..) = fold(&Level::ChatOnly, &lines, "");
        assert_eq!(steps[0].input["command"].chars().count(), 200, "a step's input is cut to 200 scalars");
        assert_eq!(steps[0].input.keys().collect::<Vec<_>>(), ["command"], "and keeps only the fields that name the work");
        assert_eq!(steps[0].state, StepState::Running, "a tool use the result never answered stays running");

        let code = |stderr: &str, lines: &str| fold(&Level::ChatOnly, lines, stderr).4.and_then(|e| e.code);
        assert_eq!(code("CLAUDE_CODE_GIT_BASH_PATH=C:\\x", "").as_deref(), Some(NEEDS_GIT));
        assert_eq!(
            code("", r#"{"type":"result","subtype":"success","is_error":true,"result":"Not logged in · Please run /login"}"#).as_deref(),
            Some(SIGNED_OUT)
        );
        let kind = |lines: &str| fold(&Level::ChatOnly, lines, "").4.map(|e| e.kind);
        assert_eq!(
            kind("{\"type\":\"assistant\",\"error\":\"billing_error\",\"message\":{\"content\":[]}}\n{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":true,\"result\":\"x\"}"),
            Some(ErrorKind::Billing)
        );
        assert_eq!(
            code("", r#"{"type":"result","subtype":"error_during_execution","is_error":true,"result":"boom"}"#).as_deref(),
            Some(CRASHED),
            "an unknown error result is a crash, never a guess"
        );
    }

    #[test]
    fn only_the_no_tools_level_checks_its_init() {
        assert_eq!((Level::NoTools.key(), Level::NoTools.folder()), ("none", None));
        assert_eq!(init_tools(&Level::NoTools), Some(&[] as &[&str]));
        assert_eq!(init_tools(&Level::ChatOnly), None);
        assert_eq!(init_tools(&Level::ReadOnly("/x".into())), None);
        assert_eq!(init_tools(&Level::Agent("/x".into())), None);
    }

    /// The Mac's `noToolsCheck` lines and verdicts, so the two ports keep one rule.
    #[test]
    fn only_what_would_show_refuses_before_init() {
        let init_ok = r#"{"type":"system","subtype":"init","session_id":"s","model":"m","tools":[],"apiKeySource":"none","claude_code_version":"2.1.0"}"#;
        let text = r#"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"hi"}}}"#;
        let tool_start = r#"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"t1","name":"Bash","input":{}}}}"#;
        let tool_use = r#"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{}}]}}"#;
        let tool_result = r#"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","is_error":false}]}}"#;
        for (name, line) in [("a text delta", text), ("a tool_use start", tool_start), ("a tool_use message", tool_use), ("a tool_result", tool_result)] {
            let mut stream = Stream::with_init_tools(init_tools(&Level::NoTools));
            stream.consume(line);
            assert!(stream.refused_tools(), "{name} before init refuses");
        }
        let mut quiet = Stream::with_init_tools(init_tools(&Level::NoTools));
        for line in [
            r#"{"type":"system","subtype":"ui_invalidate"}"#,
            r#"{"type":"rate_limit_event","rate_limit_info":{"status":"allowed"}}"#,
            r#"{"type":"assistant","error":"authentication_failed","message":{"content":[]}}"#,
        ] {
            quiet.consume(line);
        }
        assert!(!quiet.refused_tools(), "ui_invalidate, a rate limit and an assistant error before init do not refuse");
        quiet.consume(init_ok);
        assert!(!quiet.refused_tools(), "a passing init lets the run go on");
        assert_eq!(quiet.failure("").unwrap().code.as_deref(), Some(SIGNED_OUT), "and a signed-out assistant error is still signed out");

        let mut after = Stream::with_init_tools(init_tools(&Level::NoTools));
        after.consume(init_ok);
        after.consume(tool_use);
        assert!(!after.refused_tools(), "a tool_use after a passing init does not refuse (the check is pre-init only)");
        let mut text_first = Stream::with_init_tools(init_tools(&Level::NoTools));
        text_first.consume(r#"{"type":"assistant","message":{"content":[{"type":"text","text":"hi"}]}}"#);
        assert!(!text_first.refused_tools(), "a text-only assistant block before init does not refuse");
        let mut unchecked = Stream::new();
        unchecked.consume(r#"{"type":"system","subtype":"init","session_id":"s","model":"m","tools":["Read"]}"#);
        assert!(!unchecked.refused_tools(), "a level that does not check its tools never refuses");
    }

    #[test]
    fn init_must_list_exactly_the_expected_tools() {
        for line in [
            r#"{"type":"system","subtype":"init","session_id":"s","model":"m","tools":["Read"]}"#,
            r#"{"type":"system","subtype":"init","session_id":"s","model":"m","tools":["Read",1]}"#,
            r#"{"type":"system","subtype":"init","session_id":"s","model":"m","tools":"none"}"#,
            r#"{"type":"system","subtype":"init","session_id":"s","model":"m"}"#,
        ] {
            let mut stream = Stream::with_init_tools(init_tools(&Level::NoTools));
            stream.consume(line);
            assert!(stream.refused_tools(), "{line} refuses");
        }
        let mut ok = Stream::with_init_tools(init_tools(&Level::NoTools));
        ok.consume(r#"{"type":"system","subtype":"init","session_id":"s","model":"m","tools":[]}"#);
        assert!(!ok.refused_tools(), "an empty list is the expected one");
    }

    #[test]
    fn a_refused_stream_says_nothing_more() {
        let leaky = r#"{"type":"system","subtype":"init","session_id":"s","model":"m","tools":["Read"],"apiKeySource":"none","claude_code_version":"2.1.0"}"#;
        let init_ok = r#"{"type":"system","subtype":"init","session_id":"s","model":"m","tools":[],"apiKeySource":"none","claude_code_version":"2.1.0"}"#;
        let text = r#"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"hi"}}}"#;
        let mut stream = Stream::with_init_tools(init_tools(&Level::NoTools));
        let reported = stream.consume(leaky);
        assert!(matches!(reported.as_slice(), [ChatChunk::Engine(r)] if r.session_id == "s"), "the init's engine report is still reported");
        assert!(stream.consume(init_ok).is_empty(), "a clean init after a refusal gives nothing");
        assert!(stream.consume(text).is_empty(), "a text line after a refusal gives nothing");
        assert!(stream.refused_tools(), "and the refusal holds");
        let err = stream.failure("").unwrap();
        assert_eq!(err.code.as_deref(), Some(TOOLS_PRESENT));
        assert!(matches!(err.kind, ErrorKind::BadRequest), "a bad request");
        assert_eq!(err.resets_at, None);
    }

    /// A result that arrives before a refusing init: its finish is returned, but the refusal wins, so the run is never a success.
    #[test]
    fn a_finish_before_a_refusing_init_is_never_a_success() {
        let result = r#"{"type":"result","subtype":"success","is_error":false,"result":"Fixed text."}"#;
        let init_webfetch = r#"{"type":"system","subtype":"init","session_id":"s","model":"m","claude_code_version":"2.1.0","tools":["WebFetch"],"apiKeySource":"none"}"#;
        let mut stream = Stream::with_init_tools(init_tools(&Level::NoTools));
        let early = stream.consume(result);
        assert!(matches!(early.as_slice(), [ChatChunk::Finish(Finish::Stop)]), "the finish is returned: {early:?}");
        assert!(!stream.refused_tools(), "a result before init does not refuse by itself");
        stream.consume(init_webfetch);
        assert!(stream.refused_tools(), "an init listing WebFetch refuses the no-tools run");
        let err = stream.failure("").expect("a refused run is never a finish");
        assert_eq!(err.code.as_deref(), Some(TOOLS_PRESENT));
        assert!(matches!(err.kind, ErrorKind::BadRequest), "a bad request, not a success");
    }

    #[test]
    fn the_words_of_each_failure() {
        let data = testkit::load_json("claude-code/copy.json");
        for c in data["cases"].as_array().unwrap() {
            // The time of a plan limit is the webview's to format; here only the words without one.
            if c["resetsAt"].is_number() {
                continue;
            }
            let err = AiError { code: c["code"].as_str().map(str::to_string), ..AiError::new(ErrorKind::Server) };
            let note = wording(&err).unwrap_or_else(|| panic!("{}: no words", c["code"]));
            assert_eq!(note.text, c["text"].as_str().unwrap(), "{}", c["code"]);
            let action = note.action.map(|a| serde_json::to_value(a).unwrap()["kind"].as_str().unwrap().to_string());
            let expect = c["action"].as_str().map(|a| match a {
                "installGuide" => "installClaude",
                "signIn" => "signInClaude",
                "updateGuide" => "updateClaude",
                "retry" => "tryAgain",
                "gitGuide" => "installGit",
                other => other,
            });
            assert_eq!(action.as_deref(), expect, "{}: the one button", c["code"]);
        }
        assert!(wording(&AiError::new(ErrorKind::Server)).is_none(), "any other error is left to the general words");
    }
}
