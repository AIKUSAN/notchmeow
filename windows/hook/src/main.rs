//! notchmeow-hook — the relay Claude Code runs on every hook event.
//!
//! Reads the hook JSON on stdin, adds a little terminal context, and hands it to
//! NotchMeow over the named pipe `\\.\pipe\notchmeow-<sid>` (Windows) or the Unix
//! socket `$XDG_RUNTIME_DIR/notchmeow.sock` (Linux).
//!
//! Hard rule (docs/CLAUDE.md): **never block Claude Code.**
//! * If the pipe does not exist — NotchMeow is closed — we exit 0 immediately with
//!   nothing on stdout, and the session carries on untouched.
//! * Every step runs under a deadline enforced by the main thread, so a pipe that
//!   accepts the connection and then stops reading cannot wedge the session
//!   either: we abandon the worker and exit.
//! * Only `PermissionRequest` waits for an answer, because approving from the
//!   island is the whole point. No answer means empty stdout, and Claude Code
//!   asks in the terminal exactly as if NotchMeow were not installed.
//!
//! Usage: `notchmeow-hook [--agent <name>] <EventName>` (the name is also read from the JSON).
//!
//! Gemini CLI and Antigravity (`--agent gemini` / `--agent antigravity`) send
//! their own event names and field shapes; `agents.rs` translates them, and these
//! two agents read stdout as JSON, so they are answered `{}` ("no decision"); Antigravity's
//! PreToolUse is answered `{"decision":"ask"}` (see `agents::silent_answer`).

use std::io::{Read, Write};
use std::sync::mpsc;
use std::time::Duration;

/// Budget for getting a pipe connection. Beyond this Claude Code wins, always.
const CONNECT_TIMEOUT: Duration = Duration::from_millis(300);
/// Whole-run budget for an event nobody waits on: connect and write, no more.
const FIRE_AND_FORGET_BUDGET: Duration = Duration::from_secs(2);
/// How long a permission prompt may stay on screen before the terminal takes over.
const DECISION_BUDGET: Duration = Duration::from_secs(110);

/// Fields that are pointless to forward and can be enormous (a whole file read,
/// a full command output). The island never shows them. `last_assistant_message` and
/// `prompt_response` are what the assistant said: the island never reads them either, and the
/// Sidekick (sub-project F1) keeps no agent text, so the words never cross the pipe at all.
const DROPPED_FIELDS: &[&str] = &["tool_response", "transcript_path", "agent_transcript_path", "last_assistant_message", "prompt_response"];
/// Longest string forwarded for any single field; the island truncates to far
/// less than this anyway.
const MAX_FIELD_LEN: usize = 2_000;

mod agents;

#[cfg(windows)]
mod win;
#[cfg(windows)]
use win::connect;

#[cfg(target_os = "linux")]
mod unix;
#[cfg(target_os = "linux")]
use unix::connect;

/// What the relay forwards, and what it needs to know about it afterwards.
struct Event {
    /// The payload as one newline-terminated JSON line.
    line: String,
    /// The event name, Gemini CLI and Antigravity names already translated.
    name: String,
    /// The `--agent` value; empty for Claude Code.
    agent: String,
}

fn main() {
    let Some(Event { line: payload, name: event, agent }) = read_event() else { std::process::exit(0) };

    let waits_for_answer = event == "PermissionRequest";
    let budget = if waits_for_answer { DECISION_BUDGET } else { FIRE_AND_FORGET_BUDGET };

    // The worker owns every blocking call. If it overruns the budget we simply
    // stop listening and exit: the process dying takes the pipe handle with it.
    // (The release profile unwinds. If the worker panics, its sender is dropped, so
    // `recv_timeout` returns at once and the relay still exits without blocking Claude Code.)
    let (tx, rx) = mpsc::channel::<Option<String>>();
    std::thread::spawn(move || {
        let _ = tx.send(talk(&payload, waits_for_answer));
    });

    let decision = rx.recv_timeout(budget).ok().flatten();
    if let Some(json) = stdout_for(decision.as_deref(), &agent, &event) {
        let mut out = std::io::stdout();
        let _ = writeln!(out, "{json}");
        let _ = out.flush();
    }
    // Nothing printed: Claude Code asks in the terminal, as if we were not here.
    std::process::exit(0);
}

/// What goes to stdout: the island's decision when there is one. Without it,
/// nothing, so Claude Code asks in the terminal; Gemini CLI and Antigravity
/// insist on JSON, so they get `{}` (Antigravity's PreToolUse gets "ask", see
/// `agents::silent_answer`).
fn stdout_for(decision: Option<&str>, agent: &str, event: &str) -> Option<String> {
    decision
        .and_then(decision_json)
        .or_else(|| agents::silent_answer(agent, event).map(str::to_string))
}

/// The documented PermissionRequest output. Anything we do not recognise prints
/// nothing at all rather than guessing — silence is the safe answer.
/// See https://code.claude.com/docs/en/hooks
fn decision_json(decision: &str) -> Option<String> {
    let behavior = match decision.trim() {
        // "always" still answers a plain allow; remembering it is the island's
        // business, not Claude Code's.
        "allow" | "always" => r#"{"behavior":"allow"}"#.to_string(),
        "deny" => r#"{"behavior":"deny","message":"Denied from NotchMeow"}"#.to_string(),
        _ => return None,
    };
    Some(format!(
        r#"{{"hookSpecificOutput":{{"hookEventName":"PermissionRequest","decision":{behavior}}}}}"#
    ))
}

/// Reads stdin and returns the event to forward.
fn read_event() -> Option<Event> {
    let mut raw = Vec::new();
    if std::io::stdin().read_to_end(&mut raw).is_err() || raw.is_empty() {
        return None;
    }
    let args: Vec<String> = std::env::args().skip(1).collect();
    shape_event(
        raw,
        &args,
        |var| std::env::var(var).unwrap_or_default(),
        || std::env::current_dir().ok().map(|dir| dir.to_string_lossy().to_string()),
    )
}

/// The pure half of `read_event`: the bytes from stdin, the arguments after the
/// program name, the environment and the working directory in, the event out.
fn shape_event(
    mut raw: Vec<u8>,
    args: &[String],
    env: impl Fn(&str) -> String,
    current_dir: impl FnOnce() -> Option<String>,
) -> Option<Event> {
    // Some shells hand us a UTF-8 BOM; serde_json would choke on it.
    if raw.starts_with(&[0xEF, 0xBB, 0xBF]) {
        raw.drain(..3);
    }

    let mut payload = serde_json::from_slice::<serde_json::Value>(&raw).ok()?;
    let map = payload.as_object_mut()?;

    // Parse argv: "notchmeow-hook.exe [--agent <name>] [<EventName>]"
    // --agent tags the payload with nm_agent so the app routes to the right pill.
    // Absent or invalid names are validated and discarded by the app, not here.
    let mut agent = String::new();
    let mut arg_event = String::new();
    {
        let mut it = args.iter();
        while let Some(arg) = it.next() {
            if arg == "--agent" {
                agent = it.next().cloned().unwrap_or_default();
            } else if arg_event.is_empty() {
                arg_event = arg.clone();
            }
        }
    }
    // Which agent this hook was installed for. Absent means Claude Code,
    // so existing hook commands keep working unchanged, except that a session
    // started from the Claude desktop app is tagged `claude-desktop` (see `agent_tag`).
    let agent = agents::agent_tag(&agent, &env("CLAUDE_CODE_ENTRYPOINT"));
    if !agent.is_empty() {
        map.insert("nm_agent".into(), serde_json::Value::String(agent.clone()));
    }
    let raw_event = map
        .get("hook_event_name")
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .filter(|s| !s.is_empty())
        .unwrap_or(arg_event);
    // Gemini CLI and Antigravity name their events differently; Claude Code's
    // names pass through unchanged.
    let event = agents::normalize_event(&raw_event).to_string();
    map.insert("hook_event_name".into(), serde_json::Value::String(event.clone()));
    // ...and shape their tool calls and sessions differently. No-op for Claude Code.
    agents::normalize_tool_fields(map, &env("GEMINI_SESSION_ID"));

    for field in DROPPED_FIELDS {
        map.remove(*field);
    }

    let cwd_missing = map
        .get("cwd")
        .and_then(|v| v.as_str())
        .map(str::is_empty)
        .unwrap_or(true);
    if cwd_missing {
        if let Some(cwd) = agents::workspace_cwd(map).or_else(current_dir) {
            map.insert("cwd".into(), serde_json::Value::String(cwd));
        }
    }

    // Which terminal the session runs in. Unlike macOS, NotchMeow here accepts
    // events from every terminal, so this is context only — never a filter.
    for (key, var) in [
        ("term_program", "TERM_PROGRAM"),
        ("wt_session", "WT_SESSION"),
        ("term_session_id", "TERM_SESSION_ID"),
        ("vscode_pid", "VSCODE_PID"),
        ("session_pid", "CLAUDE_CODE_SSE_PORT"),
    ] {
        if !map.contains_key(key) {
            map.insert(key.into(), serde_json::Value::String(env(var)));
        }
    }

    truncate_strings(&mut payload);

    let mut line = payload.to_string();
    line.push('\n');
    Some(Event { line, name: event, agent })
}

/// Caps every string in the payload. A single Write can carry a whole file.
fn truncate_strings(value: &mut serde_json::Value) {
    match value {
        serde_json::Value::String(s) => {
            if s.len() > MAX_FIELD_LEN {
                // Cut on a char boundary; a lone byte index can split UTF-8.
                let mut end = MAX_FIELD_LEN;
                while end > 0 && !s.is_char_boundary(end) {
                    end -= 1;
                }
                s.truncate(end);
                s.push('…');
            }
        }
        serde_json::Value::Array(items) => items.iter_mut().for_each(truncate_strings),
        serde_json::Value::Object(map) => map.values_mut().for_each(truncate_strings),
        _ => {}
    }
}

/// Connect, send, and — for a permission request — wait for the island's word.
fn talk(payload: &str, waits_for_answer: bool) -> Option<String> {
    let mut pipe = connect()?;

    if pipe.write_all(payload.as_bytes()).is_err() {
        return None;
    }
    let _ = pipe.flush();

    if !waits_for_answer {
        return None;
    }

    let mut buf = Vec::new();
    let mut chunk = [0u8; 1024];
    loop {
        match pipe.read(&mut chunk) {
            Ok(0) => break,
            Ok(n) => {
                buf.extend_from_slice(&chunk[..n]);
                if buf.contains(&b'\n') {
                    break;
                }
            }
            Err(_) => break,
        }
    }
    let answer = String::from_utf8_lossy(&buf).trim().to_string();
    (!answer.is_empty()).then_some(answer)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decision_json_matches_the_documented_shape() {
        assert_eq!(
            decision_json("allow").unwrap(),
            r#"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#
        );
        assert_eq!(
            decision_json("deny").unwrap(),
            r#"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Denied from NotchMeow"}}}"#
        );
        // "always" is an island concept; Claude Code just gets an allow.
        assert!(decision_json("always").unwrap().contains(r#""behavior":"allow""#));
    }

    #[test]
    fn anything_unrecognised_prints_nothing() {
        assert!(decision_json("").is_none());
        assert!(decision_json("maybe").is_none());
        // The shape the app used to send must not be mistaken for a decision.
        assert!(decision_json(r#"{"permissionDecision":"allow"}"#).is_none());
    }

    #[test]
    fn long_strings_are_cut_on_a_char_boundary() {
        let mut v = serde_json::json!({ "tool_input": { "content": "é".repeat(4000) } });
        truncate_strings(&mut v);
        let s = v["tool_input"]["content"].as_str().unwrap();
        assert!(s.len() <= MAX_FIELD_LEN + 4);
        assert!(s.ends_with('…'));
    }

    // ── What the relay forwards for each agent ───────────────────────────────

    /// Runs the pure half of the relay the way an installed hook command would:
    /// the stdin text, the arguments after the program name, a few variables.
    fn shape(stdin: &str, args: &[&str], env: &[(&str, &str)]) -> Option<Event> {
        let args: Vec<String> = args.iter().map(|a| a.to_string()).collect();
        let lookup = |name: &str| {
            env.iter().find(|(k, _)| *k == name).map(|(_, v)| v.to_string()).unwrap_or_default()
        };
        shape_event(stdin.as_bytes().to_vec(), &args, lookup, || Some("/the/working/dir".to_string()))
    }

    fn forwarded(event: &Event) -> serde_json::Value {
        assert!(event.line.ends_with('\n') && event.line.matches('\n').count() == 1, "one line");
        serde_json::from_str(event.line.trim_end()).expect("the line is JSON")
    }

    #[test]
    fn a_gemini_cli_tool_event_is_forwarded_as_the_agents_pre_tool_use() {
        let stdin = r#"{"hook_event_name":"BeforeTool","session_id":"g-1","cwd":"/proj","tool_name":"run_shell_command","tool_input":{"command":"ls"}}"#;
        let event = shape(stdin, &["--agent", "gemini", "PreToolUse"], &[]).unwrap();
        assert_eq!((event.name.as_str(), event.agent.as_str()), ("PreToolUse", "gemini"));
        let sent = forwarded(&event);
        assert_eq!(sent["hook_event_name"], "PreToolUse");
        assert_eq!(sent["nm_agent"], "gemini");
        assert_eq!(sent["session_id"], "g-1");
        assert_eq!(sent["cwd"], "/proj");
        assert_eq!(sent["tool_name"], "run_shell_command");
        assert_eq!(sent["tool_input"]["command"], "ls");
    }

    #[test]
    fn the_event_named_on_the_command_line_is_used_when_the_payload_has_none() {
        let event = shape(r#"{"session_id":"g-1"}"#, &["--agent", "gemini", "Stop"], &[]).unwrap();
        assert_eq!(event.name, "Stop");
        assert_eq!(forwarded(&event)["hook_event_name"], "Stop");
    }

    #[test]
    fn an_antigravity_invocation_event_gets_its_session_and_folder_from_the_payload() {
        let stdin = r#"{"hook_event_name":"PreInvocation","conversationId":"conv-9","workspacePaths":["/proj","/other"]}"#;
        let event = shape(stdin, &["--agent", "antigravity", "PreInvocation"], &[]).unwrap();
        assert_eq!(event.name, "UserPromptSubmit");
        let sent = forwarded(&event);
        assert_eq!(sent["nm_agent"], "antigravity");
        assert_eq!(sent["session_id"], "conv-9");
        assert_eq!(sent["cwd"], "/proj", "workspacePaths beats the working directory");
    }

    #[test]
    fn an_antigravity_tool_call_is_forwarded_the_way_the_island_reads_it() {
        let stdin = r#"{"toolCall":{"name":"example_tool","args":{"FilePath":"/proj/a.rs"}},"conversationId":"conv-9"}"#;
        let event = shape(stdin, &["--agent", "antigravity", "PostToolUse"], &[]).unwrap();
        let sent = forwarded(&event);
        assert_eq!(sent["hook_event_name"], "PostToolUse");
        assert_eq!(sent["tool_name"], "example_tool");
        assert_eq!(sent["tool_input"]["file_path"], "/proj/a.rs");
        assert_eq!(sent["cwd"], "/the/working/dir", "no workspace and no cwd: the working directory");
    }

    #[test]
    fn the_gemini_session_variable_is_the_last_resort() {
        let stdin = r#"{"hook_event_name":"SessionStart"}"#;
        let event = shape(stdin, &["--agent", "gemini", "SessionStart"], &[("GEMINI_SESSION_ID", "env-5")]).unwrap();
        assert_eq!(forwarded(&event)["session_id"], "env-5");
        let event = shape(stdin, &["--agent", "gemini", "SessionStart"], &[]).unwrap();
        assert!(forwarded(&event).get("session_id").is_none());
    }

    #[test]
    fn a_claude_code_event_is_forwarded_as_before() {
        let stdin = r#"{"hook_event_name":"PreToolUse","session_id":"c-1","cwd":"/proj","tool_name":"Bash","tool_input":{"command":"ls"},"tool_response":"big","transcript_path":"/t"}"#;
        let event = shape(stdin, &["PreToolUse"], &[("TERM_PROGRAM", "vscode")]).unwrap();
        assert_eq!((event.name.as_str(), event.agent.as_str()), ("PreToolUse", ""));
        let sent = forwarded(&event);
        assert_eq!(
            sent,
            serde_json::json!({
                "hook_event_name": "PreToolUse", "session_id": "c-1", "cwd": "/proj",
                "tool_name": "Bash", "tool_input": { "command": "ls" },
                "term_program": "vscode", "wt_session": "", "term_session_id": "",
                "vscode_pid": "", "session_pid": ""
            }),
            "no nm_agent, nothing translated, the two big fields dropped"
        );
        // A Claude Code permission request still waits for the island's answer.
        let ask = shape(r#"{"hook_event_name":"PermissionRequest","tool_name":"Bash"}"#, &[], &[]).unwrap();
        assert_eq!(ask.name, "PermissionRequest");
    }

    /// Subagent kittens (sub-project B): the island reads `agent_id` and `agent_type` from tool, permission and SubagentStart/SubagentStop events. The relay only
    /// drops the big and the private fields (`DROPPED_FIELDS`), so both pass through.
    #[test]
    fn a_subagents_agent_id_and_agent_type_reach_the_island() {
        let stdin = r#"{"hook_event_name":"PreToolUse","session_id":"c-1","agent_id":"a1","agent_type":"Explore","tool_name":"Grep","tool_input":{},"tool_response":"big","transcript_path":"/t"}"#;
        let sent = forwarded(&shape(stdin, &["PreToolUse"], &[]).unwrap());
        assert_eq!((&sent["agent_id"], &sent["agent_type"]), (&serde_json::json!("a1"), &serde_json::json!("Explore")));
        assert!(sent.get("tool_response").is_none() && sent.get("transcript_path").is_none());
        for name in ["SubagentStart", "SubagentStop", "PermissionRequest"] {
            let stdin = format!(r#"{{"hook_event_name":"{name}","session_id":"c-1","agent_id":"a1","agent_type":"Plan"}}"#);
            let sent = forwarded(&shape(&stdin, &[name], &[]).unwrap());
            assert_eq!((&sent["agent_id"], &sent["agent_type"]), (&serde_json::json!("a1"), &serde_json::json!("Plan")), "{name}");
        }
    }

    /// The Sidekick (sub-project F1) keeps no agent text and never reads a transcript: the relay does not carry them, so a leak test has nothing to find on this side of the pipe.
    #[test]
    fn the_assistants_words_and_the_transcript_never_cross_the_pipe() {
        let stdin = r#"{"hook_event_name":"Stop","session_id":"c-1","cwd":"C:/work/app","last_assistant_message":"SECRET-WORDS","prompt_response":"SECRET-REPLY","transcript_path":"C:/Users/me/.claude/SECRET-TRANSCRIPT.jsonl","tool_response":{"stdout":"SECRET-OUT"}}"#;
        let event = shape(stdin, &["Stop"], &[]).unwrap();
        for secret in ["SECRET-WORDS", "SECRET-REPLY", "SECRET-TRANSCRIPT", "SECRET-OUT"] {
            assert!(!event.line.contains(secret), "{secret} crossed the pipe: {}", event.line);
        }
        // A subagent's own transcript path is a transcript too: a SubagentStop carries it under its own name, and it must not cross either.
        let sub = r#"{"hook_event_name":"SubagentStop","session_id":"c-1","agent_id":"a1","agent_transcript_path":"C:/Users/me/.claude/SECRET-SUBTRANSCRIPT.jsonl"}"#;
        let sub_event = shape(sub, &["SubagentStop"], &[]).unwrap();
        assert!(!sub_event.line.contains("SECRET-SUBTRANSCRIPT"), "the subagent's transcript crossed the pipe: {}", sub_event.line);
        let sent = forwarded(&event);
        assert_eq!((&sent["hook_event_name"], &sent["session_id"], &sent["cwd"]), (&serde_json::json!("Stop"), &serde_json::json!("c-1"), &serde_json::json!("C:/work/app")));
        // What the island and the Sidekick do read still passes: the prompt (the island's step row), the message of a Notification, the tool and its input.
        let tool = r#"{"hook_event_name":"PostToolUse","session_id":"c-1","prompt":"fix it","message":"hello","tool_name":"Bash","tool_input":{"command":"ls"}}"#;
        let sent = forwarded(&shape(tool, &["PostToolUse"], &[]).unwrap());
        assert_eq!((&sent["prompt"], &sent["message"], &sent["tool_input"]["command"]), (&serde_json::json!("fix it"), &serde_json::json!("hello"), &serde_json::json!("ls")));
    }

    #[test]
    fn a_payload_the_relay_cannot_use_forwards_nothing() {
        for stdin in ["", "not json", "[1,2]", "\"text\"", "{"] {
            assert!(shape(stdin, &["--agent", "gemini", "Stop"], &[]).is_none(), "{stdin:?}");
        }
        // A BOM in front of good JSON is stripped, not fatal.
        let with_bom = format!("\u{feff}{}", r#"{"hook_event_name":"Stop"}"#);
        assert!(shape(&with_bom, &[], &[]).is_some());
    }

    #[test]
    fn a_claude_desktop_session_is_forwarded_with_its_tag() {
        let stdin = r#"{"hook_event_name":"Stop","session_id":"d-1","cwd":"/proj"}"#;
        let desktop = shape(stdin, &["Stop"], &[("CLAUDE_CODE_ENTRYPOINT", "claude-desktop")]).unwrap();
        assert_eq!(desktop.agent, "claude-desktop");
        assert_eq!(forwarded(&desktop)["nm_agent"], "claude-desktop");
        let explicit = shape(stdin, &["--agent", "gemini", "Stop"], &[("CLAUDE_CODE_ENTRYPOINT", "claude-desktop")]).unwrap();
        assert_eq!(forwarded(&explicit)["nm_agent"], "gemini", "an explicit --agent wins");
        for entry in ["cli", "vscode", ""] {
            let plain = shape(stdin, &["Stop"], &[("CLAUDE_CODE_ENTRYPOINT", entry)]).unwrap();
            assert!(forwarded(&plain).get("nm_agent").is_none(), "{entry:?} is plain Claude Code");
        }
    }

    #[test]
    fn a_dangling_agent_flag_names_no_agent() {
        let event = shape(r#"{"hook_event_name":"Stop"}"#, &["--agent"], &[]).unwrap();
        assert_eq!(event.agent, "");
        assert!(forwarded(&event).get("nm_agent").is_none());
    }

    #[test]
    fn only_gemini_and_antigravity_are_answered_with_json_when_there_is_no_decision() {
        assert_eq!(stdout_for(None, "gemini", "PreToolUse").as_deref(), Some("{}"));
        assert_eq!(stdout_for(None, "antigravity", "Stop").as_deref(), Some("{}"));
        assert_eq!(stdout_for(None, "", "PreToolUse"), None, "Claude Code: silence");
        assert_eq!(stdout_for(None, "codex", "PreToolUse"), None);
        // Antigravity reads `{}` on PreToolUse as a denial: it is asked, which leaves the choice to its own prompt.
        assert_eq!(stdout_for(None, "antigravity", "PreToolUse").as_deref(), Some(r#"{"decision":"ask"}"#));
        // A decision from the island is never replaced by the empty answer.
        assert!(stdout_for(Some("allow"), "gemini", "PermissionRequest").unwrap().contains(r#""behavior":"allow""#));
        // An answer nobody recognises is silence for Claude Code, and `{}` for Gemini.
        assert_eq!(stdout_for(Some("maybe"), "", "PermissionRequest"), None);
        assert_eq!(stdout_for(Some("maybe"), "gemini", "PermissionRequest").as_deref(), Some("{}"));
    }
}
