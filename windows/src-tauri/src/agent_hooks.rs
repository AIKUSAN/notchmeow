// Gemini CLI and Antigravity (`agy`) hook installation.
//
// The rules are the ones hooks.rs follows for Claude Code, and CLAUDE.md's: read
// the file and refuse anything unreadable or of an unexpected shape, show the
// diff, take a dated backup, merge without touching anybody else's entries, and
// write only after an explicit click, and only if the file is still the one the
// user looked at. Uninstall removes NotchMeow's entries and nothing else.
//
// What goes into the files is the macOS app's, entry for entry (HookServer.swift):
//
//   Gemini CLI   ~/.gemini/settings.json      six events, matcher "*", timeouts in ms
//   Antigravity  ~/.gemini/config/hooks.json  under the key "notchmeow", five
//                events, timeouts in seconds; the two tool events take a matcher
//                group, the three lifecycle events a direct handler
//
// Every command is the relay's path, `--agent <name>` and the event name the
// island understands (the relay translates the agents' own names as well).

use std::path::{Path, PathBuf};

use serde_json::{json, Map, Value};

use crate::hooks::{self, HookPreview, HookStatus};
use crate::{platform, settings};

/// The two agents. The tag is what `--agent` carries, what the island routes on
/// (`nm_agent`, so the pills `agent_gemini` and `agent_antigravity`) and what the
/// settings window sends to the commands in lib.rs.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Agent {
    Gemini,
    Antigravity,
}

impl Agent {
    pub fn from_tag(tag: &str) -> Result<Agent, String> {
        match tag {
            "gemini" => Ok(Agent::Gemini),
            "antigravity" => Ok(Agent::Antigravity),
            other => Err(format!("unknown agent \"{other}\"")),
        }
    }

    fn tag(self) -> &'static str {
        match self {
            Agent::Gemini => "gemini",
            Agent::Antigravity => "antigravity",
        }
    }

    fn label(self) -> &'static str {
        match self {
            Agent::Gemini => "Gemini CLI",
            Agent::Antigravity => "Antigravity",
        }
    }

    /// `%USERPROFILE%\.gemini\settings.json`, `%USERPROFILE%\.gemini\config\hooks.json`
    /// (and the same under `$HOME` on Linux).
    pub fn path(self) -> PathBuf {
        let dir = platform::home_dir().join(".gemini");
        match self {
            Agent::Gemini => dir.join("settings.json"),
            Agent::Antigravity => dir.join("config").join("hooks.json"),
        }
    }
}

/// Gemini CLI: its event, the name the relay is told, the timeout in milliseconds.
/// `AfterModel` is not installed: it fires on every streamed chunk and would
/// flood the island.
const GEMINI_EVENTS: &[(&str, &str, u64)] = &[
    ("SessionStart", "SessionStart", 10_000),
    ("SessionEnd", "SessionEnd", 10_000),
    ("BeforeTool", "PreToolUse", 5_000),
    ("AfterTool", "PostToolUse", 5_000),
    ("BeforeAgent", "UserPromptSubmit", 5_000),
    ("AfterAgent", "Stop", 5_000),
];

/// Antigravity: its event, and whether it takes a matcher group (the tool events)
/// or a direct handler (the lifecycle events).
const AGY_EVENTS: &[(&str, bool)] = &[
    ("PreToolUse", true),
    ("PostToolUse", true),
    ("PreInvocation", false),
    ("PostInvocation", false),
    ("Stop", false),
];

/// Antigravity's timeouts are in seconds.
const AGY_TIMEOUT_S: u64 = 10;

/// The top-level key of `hooks.json` that holds NotchMeow's entries.
const AGY_KEY: &str = "notchmeow";

// ── The command a hook runs ───────────────────────────────────────────────────

/// The quoted exe path in forward slashes, as hooks.rs writes it for Claude Code
/// on Windows. Not cfg-gated, so every OS can test it.
#[cfg(any(windows, test))]
fn windows_command(exe: &str, agent: &str, event: &str) -> String {
    format!("\"{}\" --agent {agent} {event}", exe.replace('\\', "/"))
}

/// A single-quoted path, as hooks.rs writes it for Claude Code on Linux.
#[cfg(unix)]
fn unix_command(exe: &str, agent: &str, event: &str) -> String {
    format!("{} --agent {agent} {event}", hooks::sh_quote(exe))
}

#[cfg(windows)]
fn relay_command(agent: &str, event: &str) -> String {
    windows_command(&settings::hook_exe_path().to_string_lossy(), agent, event)
}

#[cfg(unix)]
fn relay_command(agent: &str, event: &str) -> String {
    unix_command(&settings::hook_exe_path().to_string_lossy(), agent, event)
}

// ── Merging ───────────────────────────────────────────────────────────────────

/// True when `entry` (a hook group, or a hook inside one, or an older flat entry)
/// runs NotchMeow's relay.
fn runs_relay(entry: &Value) -> bool {
    entry
        .get("command")
        .and_then(Value::as_str)
        .is_some_and(|command| command.contains(hooks::MARKER))
}

/// True when `entry` runs the relay for `agent` (`--agent gemini`).
fn runs_relay_for(entry: &Value, agent: Agent) -> bool {
    entry
        .get("command")
        .and_then(Value::as_str)
        .is_some_and(|c| c.contains(hooks::MARKER) && c.contains(&format!("--agent {}", agent.tag())))
}

/// `groups` without NotchMeow's hooks. A group that also holds somebody else's
/// hooks stays, minus ours; a group that held only ours goes, and so does an
/// older flat entry (`command` on the group itself).
fn strip_ours(groups: &[Value]) -> Vec<Value> {
    groups
        .iter()
        .filter_map(|group| {
            if runs_relay(group) {
                return None;
            }
            let Some(inner) = group.get("hooks").and_then(Value::as_array) else {
                return Some(group.clone());
            };
            let kept: Vec<Value> = inner.iter().filter(|hook| !runs_relay(hook)).cloned().collect();
            if kept.is_empty() && !inner.is_empty() {
                return None;
            }
            let mut updated = group.clone();
            updated["hooks"] = Value::Array(kept);
            Some(updated)
        })
        .collect()
}

/// The event's groups, or an error when it is not a list of objects.
fn groups_of(hooks: &Map<String, Value>, event: &str) -> Result<Vec<Value>, String> {
    match hooks.get(event) {
        None => Ok(Vec::new()),
        Some(Value::Array(list)) if list.iter().all(Value::is_object) => Ok(list.clone()),
        Some(_) => Err(format!("\"hooks\"[\"{event}\"] has an unexpected type — NotchMeow has not touched it.")),
    }
}

/// The `hooks` object, an empty one when there is none, an error for anything else.
fn hooks_object(root: &Map<String, Value>) -> Result<Map<String, Value>, String> {
    match root.get("hooks") {
        None => Ok(Map::new()),
        Some(Value::Object(map)) => Ok(map.clone()),
        Some(_) => Err("\"hooks\" has an unexpected type — NotchMeow has not touched it.".to_string()),
    }
}

/// Builds the command a hook runs from the agent's tag and the event name:
/// `relay_command` in production, a fixed string in the tests.
type CommandFor<'a> = &'a dyn Fn(&str, &str) -> String;

/// Gemini CLI settings with NotchMeow's six hooks added; everything else is left alone.
fn merged_gemini(existing: &Value, command: CommandFor) -> Result<Value, String> {
    let mut root = existing.as_object().cloned().unwrap_or_default();
    let mut hooks = hooks_object(&root)?;
    for (event, normalized, timeout_ms) in GEMINI_EVENTS {
        let mut groups = strip_ours(&groups_of(&hooks, event)?);
        groups.push(json!({
            "matcher": "*",
            "hooks": [{
                "type": "command",
                "command": command(Agent::Gemini.tag(), normalized),
                "timeout": timeout_ms,
            }]
        }));
        hooks.insert((*event).to_string(), Value::Array(groups));
    }
    root.insert("hooks".into(), Value::Object(hooks));
    Ok(Value::Object(root))
}

/// Gemini CLI settings with every NotchMeow hook removed, and nothing else changed.
fn without_gemini(existing: &Value) -> Result<Value, String> {
    let mut root = existing.as_object().cloned().unwrap_or_default();
    let hooks = hooks_object(&root)?;
    let mut kept = Map::new();
    for (event, value) in &hooks {
        let groups = match value {
            Value::Array(list) if list.iter().all(Value::is_object) => list,
            other => {
                kept.insert(event.clone(), other.clone());
                continue;
            }
        };
        let cleaned = strip_ours(groups);
        // An event that held only ours goes; one that was empty before stays.
        if cleaned.is_empty() && !groups.is_empty() {
            continue;
        }
        kept.insert(event.clone(), Value::Array(cleaned));
    }
    if kept.is_empty() && !hooks.is_empty() {
        root.remove("hooks");
    } else if root.contains_key("hooks") {
        root.insert("hooks".into(), Value::Object(kept));
    }
    Ok(Value::Object(root))
}

/// Antigravity hooks with NotchMeow's five added under its own key.
fn merged_agy(existing: &Value, command: CommandFor) -> Value {
    let mut root = existing.as_object().cloned().unwrap_or_default();
    let mut ours = Map::new();
    for (event, takes_matcher) in AGY_EVENTS {
        let hook = json!({
            "type": "command",
            "command": command(Agent::Antigravity.tag(), event),
            "timeout": AGY_TIMEOUT_S,
        });
        let entry = if *takes_matcher { json!([{ "matcher": "*", "hooks": [hook] }]) } else { json!([hook]) };
        ours.insert((*event).to_string(), entry);
    }
    root.insert(AGY_KEY.into(), Value::Object(ours));
    Value::Object(root)
}

/// Antigravity hooks without NotchMeow's key.
fn without_agy(existing: &Value) -> Value {
    let mut root = existing.as_object().cloned().unwrap_or_default();
    root.remove(AGY_KEY);
    Value::Object(root)
}

fn plan(agent: Agent, current: &Value, install: bool) -> Result<Value, String> {
    match (agent, install) {
        (Agent::Gemini, true) => merged_gemini(current, &relay_command),
        (Agent::Gemini, false) => without_gemini(current),
        (Agent::Antigravity, true) => Ok(merged_agy(current, &relay_command)),
        (Agent::Antigravity, false) => Ok(without_agy(current)),
    }
}

/// Whether NotchMeow's hooks are in `value`: for Gemini CLI any hook that runs the
/// relay with `--agent gemini`, for Antigravity anything under its own key that runs it.
fn installed_in(agent: Agent, value: &Value) -> bool {
    match agent {
        Agent::Gemini => value
            .get("hooks")
            .and_then(Value::as_object)
            .is_some_and(|hooks| {
                hooks.values().filter_map(Value::as_array).flatten().any(|group| {
                    runs_relay_for(group, agent)
                        || group
                            .get("hooks")
                            .and_then(Value::as_array)
                            .is_some_and(|inner| inner.iter().any(|hook| runs_relay_for(hook, agent)))
                })
            }),
        Agent::Antigravity => value
            .get(AGY_KEY)
            .and_then(|ours| serde_json::to_string(ours).ok())
            .is_some_and(|text| text.contains(hooks::MARKER)),
    }
}

// ── The file ──────────────────────────────────────────────────────────────────

/// The file as JSON. Absent or empty: an empty object. Anything we cannot read or
/// parse is an error: it must never be mistaken for empty and written over.
fn read(path: &Path) -> Result<Value, String> {
    match std::fs::read(path) {
        Ok(bytes) => hooks::parse_settings(&bytes, &path.display().to_string()),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(Value::Object(Map::new())),
        Err(err) => Err(format!("Can't read {}: {err}", path.display())),
    }
}

fn fingerprint_of(path: &Path) -> String {
    hooks::fingerprint(&std::fs::read(path).unwrap_or_default())
}

/// `settings.json.bak-20261005-101500`, beside the file; empty when there is no
/// file yet, so nothing is backed up (the settings window says "created" then).
fn backup_path(path: &Path) -> String {
    if !path.exists() {
        return String::new();
    }
    let name = path.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
    path.with_file_name(format!("{name}.bak-{}", hooks::stamp())).to_string_lossy().to_string()
}

/// What an agent's card says when its config file is there but cannot be used (Gemini's settings.json, Antigravity's hooks.json).
pub const UNREADABLE_CONFIG: &str = "Couldn't read the config file.";

/// The file as an install reads it: `read`, then the planner. A file that either refuses is not usable, so `preview` and `write` refuse it too, and the
/// status says so with the same classifier.
fn usable(agent: Agent, path: &Path) -> Result<(), String> {
    let current = read(path)?;
    plan(agent, &current, true).map(|_| ())
}

fn status_at(agent: Agent, path: &Path) -> HookStatus {
    let hook_path = settings::hook_exe_path();
    let reason = usable(agent, path).err().map(|err| hooks::reason_of(&err));
    if let Some(reason) = reason {
        crate::log::line(format!("{} config cannot be used: {reason}", agent.label()));
    }
    HookStatus {
        installed: read(path).map(|current| installed_in(agent, &current)).unwrap_or(false),
        settings_path: path.to_string_lossy().to_string(),
        hook_ready: hook_path.exists(),
        hook_path: hook_path.to_string_lossy().to_string(),
        error: reason.map(|_| UNREADABLE_CONFIG.to_string()),
        reason: reason.map(String::from),
    }
}

fn preview_at(agent: Agent, path: &Path, install: bool) -> Result<HookPreview, String> {
    if !install && !path.exists() {
        return Err(format!("No {} hooks to remove.", agent.label()));
    }
    let current = read(path)?;
    let next = plan(agent, &current, install).map_err(|e| format!("{}: {e}", path.display()))?;
    Ok(HookPreview {
        diff: hooks::unified_diff(&hooks::pretty(&current), &hooks::pretty(&next)),
        backup: backup_path(path),
        settings_path: path.to_string_lossy().to_string(),
        fingerprint: fingerprint_of(path),
    })
}

/// Writes the merged (or cleaned) file after a dated backup, and returns the
/// backup's path (empty when there was no file to back up). Everything that can
/// refuse does so first, before the backup, so a refusal leaves nothing behind:
/// no backup, no new folder, no half a file.
fn write_at(agent: Agent, path: &Path, install: bool, fingerprint: &str) -> Result<String, String> {
    let current = read(path)?;
    if fingerprint_of(path) != fingerprint {
        return Err(format!(
            "{} changed since the preview. Nothing was written — review the new diff.",
            path.display()
        ));
    }
    let next = plan(agent, &current, install).map_err(|e| format!("{}: {e}", path.display()))?;

    let backup = backup_path(path);
    if !backup.is_empty() {
        std::fs::copy(path, &backup).map_err(|e| format!("backup failed: {e}"))?;
    }
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    }
    let mut text = hooks::pretty(&next);
    text.push('\n');
    hooks::replace_file(path, &text)?;
    Ok(backup)
}

// ── Public API (the commands in lib.rs) ───────────────────────────────────────

pub fn status(agent: Agent) -> HookStatus {
    status_at(agent, &agent.path())
}

/// The diff the user has to look at before anything is written.
pub fn preview(agent: Agent, install: bool) -> Result<HookPreview, String> {
    preview_at(agent, &agent.path(), install)
}

/// Only ever called from an explicit click in the settings window, with the
/// fingerprint of the preview the user looked at.
pub fn write(agent: Agent, install: bool, fingerprint: &str) -> Result<String, String> {
    write_at(agent, &agent.path(), install, fingerprint)
}

#[cfg(test)]
mod tests {
    use super::*;

    // The merge functions take the command builder, so these tests do not depend on
    // where this machine keeps the relay (hooks.rs's own test changes the home
    // directory, process-wide, while the tests run side by side).
    fn fake(agent: &str, event: &str) -> String {
        format!("{} --agent {agent} {event}", hooks::MARKER)
    }

    fn gemini_command(event: &str) -> String {
        fake("gemini", event)
    }

    /// A temp directory of its own per test; nothing here touches the real home.
    fn temp_dir(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("notchmeow-agent-hooks-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn foreign_gemini() -> Value {
        json!({
            "model": "gemini-3-pro",
            "theme": "dark",
            "mcpServers": { "x": { "command": "x" } },
            "hooks": {
                "BeforeTool": [
                    { "matcher": "write_file", "hooks": [{ "type": "command", "command": "someone-elses-tool", "timeout": 1000 }] }
                ],
                "Notification": [
                    { "hooks": [{ "type": "command", "command": "keep-me" }] }
                ]
            }
        })
    }

    // ── Gemini CLI ───────────────────────────────────────────────────────────

    #[test]
    fn installing_gemini_hooks_adds_the_six_events_with_the_macs_timeouts() {
        let after = merged_gemini(&json!({}), &fake).unwrap();
        let hooks = after["hooks"].as_object().unwrap();
        assert_eq!(hooks.len(), 6);
        for (event, normalized, timeout) in [
            ("SessionStart", "SessionStart", 10_000),
            ("SessionEnd", "SessionEnd", 10_000),
            ("BeforeTool", "PreToolUse", 5_000),
            ("AfterTool", "PostToolUse", 5_000),
            ("BeforeAgent", "UserPromptSubmit", 5_000),
            ("AfterAgent", "Stop", 5_000),
        ] {
            assert_eq!(
                hooks[event],
                json!([{ "matcher": "*", "hooks": [{
                    "type": "command", "command": gemini_command(normalized), "timeout": timeout
                }] }]),
                "{event}"
            );
        }
        assert!(!hooks.contains_key("AfterModel"), "it fires on every chunk and would flood the island");
        assert!(gemini_command("Stop").contains("--agent gemini Stop"));
    }

    #[test]
    fn gemini_install_keeps_every_other_setting_and_every_foreign_hook() {
        let existing = foreign_gemini();
        let after = merged_gemini(&existing, &fake).unwrap();
        assert_eq!(after["model"], "gemini-3-pro");
        assert_eq!(after["theme"], "dark");
        assert_eq!(after["mcpServers"], existing["mcpServers"]);
        let before_tool = after["hooks"]["BeforeTool"].as_array().unwrap();
        assert_eq!(before_tool.len(), 2, "the other tool's group and ours");
        assert_eq!(before_tool[0], existing["hooks"]["BeforeTool"][0]);
        assert_eq!(after["hooks"]["Notification"], existing["hooks"]["Notification"]);
    }

    #[test]
    fn gemini_install_twice_is_install_once_and_uninstall_restores_the_file() {
        for existing in [json!({}), json!({ "model": "m" }), foreign_gemini()] {
            let once = merged_gemini(&existing, &fake).unwrap();
            assert_eq!(merged_gemini(&once, &fake).unwrap(), once, "no duplicates");
            assert_eq!(without_gemini(&once).unwrap(), existing, "uninstall puts it back exactly");
        }
    }

    #[test]
    fn a_foreign_hook_in_the_same_group_as_ours_survives_both_ways() {
        let existing = json!({ "hooks": { "BeforeTool": [{ "matcher": "*", "hooks": [
            { "type": "command", "command": "foreign" },
            { "type": "command", "command": gemini_command("PreToolUse"), "timeout": 5000 }
        ] }] } });
        let expected = json!([{ "matcher": "*", "hooks": [{ "type": "command", "command": "foreign" }] }]);
        assert_eq!(without_gemini(&existing).unwrap()["hooks"]["BeforeTool"], expected);
        let reinstalled = merged_gemini(&existing, &fake).unwrap();
        assert_eq!(reinstalled["hooks"]["BeforeTool"][0], expected[0]);
        assert_eq!(reinstalled["hooks"]["BeforeTool"].as_array().unwrap().len(), 2);
    }

    #[test]
    fn an_older_flat_entry_is_removed_and_a_foreign_flat_entry_is_kept() {
        let existing = json!({ "hooks": { "AfterTool": [
            { "type": "command", "command": gemini_command("PostToolUse") },
            { "type": "command", "command": "foreign-flat" }
        ] } });
        let cleaned = without_gemini(&existing).unwrap();
        assert_eq!(cleaned["hooks"]["AfterTool"], json!([{ "type": "command", "command": "foreign-flat" }]));
        assert_eq!(merged_gemini(&existing, &fake).unwrap()["hooks"]["AfterTool"][0], cleaned["hooks"]["AfterTool"][0]);
    }

    #[test]
    fn an_empty_event_or_group_that_is_not_ours_is_left_alone() {
        let existing = json!({ "hooks": { "SessionStart": [], "Stop": [{ "hooks": [] }] } });
        assert_eq!(without_gemini(&existing).unwrap(), existing);
    }

    #[test]
    fn unexpected_shapes_are_refused_and_never_replaced() {
        for existing in [
            json!({ "hooks": [] }),
            json!({ "hooks": "x" }),
            json!({ "hooks": null }),
            json!({ "hooks": { "BeforeTool": {} } }),
            json!({ "hooks": { "SessionStart": "x" } }),
            json!({ "hooks": { "AfterAgent": null } }),
            json!({ "hooks": { "SessionEnd": [1, 2] } }),
        ] {
            let err = merged_gemini(&existing, &fake).unwrap_err();
            assert!(err.contains("unexpected type") && err.contains("has not touched it"), "{existing}: {err}");
        }
        // Uninstall refuses the same top-level shapes, and leaves odd events alone.
        assert!(without_gemini(&json!({ "hooks": [] })).is_err());
        let odd = json!({ "hooks": { "Custom": { "a": 1 }, "Other": "x" } });
        assert_eq!(without_gemini(&odd).unwrap(), odd);
    }

    #[test]
    fn gemini_detection_needs_our_relay_and_the_gemini_tag() {
        assert!(!installed_in(Agent::Gemini, &json!({})));
        assert!(!installed_in(Agent::Gemini, &foreign_gemini()));
        assert!(installed_in(Agent::Gemini, &merged_gemini(&json!({}), &fake).unwrap()));
        // Our relay for another agent is not Gemini CLI's hook.
        let other = json!({ "hooks": { "Stop": [{ "hooks": [{ "command": fake("codex", "Stop") }] }] } });
        assert!(!installed_in(Agent::Gemini, &other));
        // An older flat entry counts too.
        let flat = json!({ "hooks": { "Stop": [{ "command": gemini_command("Stop") }] } });
        assert!(installed_in(Agent::Gemini, &flat));
    }

    // ── Antigravity ──────────────────────────────────────────────────────────

    #[test]
    fn installing_antigravity_hooks_adds_five_events_under_the_notchmeow_key() {
        let after = merged_agy(&json!({}), &fake);
        let ours = after[AGY_KEY].as_object().unwrap();
        assert_eq!(ours.len(), 5);
        let hook = |event: &str| json!({
            "type": "command", "command": fake("antigravity", event), "timeout": 10
        });
        // The tool events take a matcher group; the lifecycle events a direct handler.
        for event in ["PreToolUse", "PostToolUse"] {
            assert_eq!(ours[event], json!([{ "matcher": "*", "hooks": [hook(event)] }]), "{event}");
        }
        for event in ["PreInvocation", "PostInvocation", "Stop"] {
            assert_eq!(ours[event], json!([hook(event)]), "{event}");
        }
        assert!(fake("antigravity", "Stop").contains("--agent antigravity Stop"));
    }

    #[test]
    fn antigravity_install_and_uninstall_touch_only_the_notchmeow_key() {
        let existing = json!({ "mine": { "PreToolUse": [{ "command": "x" }] }, "other": 1 });
        let once = merged_agy(&existing, &fake);
        assert_eq!(once["mine"], existing["mine"]);
        assert_eq!(once["other"], 1);
        assert_eq!(merged_agy(&once, &fake), once, "install twice is install once");
        assert_eq!(without_agy(&once), existing, "uninstall puts it back exactly");
        assert_eq!(without_agy(&existing), existing, "nothing to remove is no change");
    }

    #[test]
    fn antigravity_detection_looks_only_under_the_notchmeow_key() {
        assert!(!installed_in(Agent::Antigravity, &json!({})));
        assert!(!installed_in(Agent::Antigravity, &json!({ "mine": { "x": hooks::MARKER } })));
        assert!(installed_in(Agent::Antigravity, &merged_agy(&json!({}), &fake)));
        assert!(!installed_in(Agent::Antigravity, &json!({ AGY_KEY: { "Stop": [{ "command": "foreign" }] } })));
    }

    // ── The command ──────────────────────────────────────────────────────────

    #[test]
    fn a_windows_command_is_a_quoted_path_in_forward_slashes() {
        assert_eq!(
            windows_command(r"C:\Users\Zoé Smith\AppData\Local\NotchMeow\bin\notchmeow-hook.exe", "gemini", "PreToolUse"),
            r#""C:/Users/Zoé Smith/AppData/Local/NotchMeow/bin/notchmeow-hook.exe" --agent gemini PreToolUse"#
        );
    }

    #[cfg(unix)]
    #[test]
    fn a_unix_command_is_one_single_quoted_word_whatever_the_path_holds() {
        assert_eq!(
            unix_command("/home/a b/.local/share/notchmeow/bin/notchmeow-hook", "antigravity", "Stop"),
            "'/home/a b/.local/share/notchmeow/bin/notchmeow-hook' --agent antigravity Stop"
        );
        assert_eq!(unix_command("/h/it's/$(id)/hook", "gemini", "Stop"), r"'/h/it'\''s/$(id)/hook' --agent gemini Stop");
    }

    #[test]
    fn the_relay_command_runs_the_relay_this_app_installs() {
        let command = relay_command("gemini", "PreToolUse");
        assert!(command.contains(hooks::MARKER), "{command}");
        assert!(command.ends_with(" --agent gemini PreToolUse"), "{command}");
    }

    // ── The files ────────────────────────────────────────────────────────────

    #[test]
    fn the_agents_files_are_where_the_mac_puts_them() {
        assert_eq!(Agent::from_tag("gemini"), Ok(Agent::Gemini));
        assert_eq!(Agent::from_tag("antigravity"), Ok(Agent::Antigravity));
        for bad in ["", "claude", "codex", "Gemini", "../x"] {
            assert!(Agent::from_tag(bad).is_err(), "{bad}");
        }
        let gemini = Agent::Gemini.path();
        let agy = Agent::Antigravity.path();
        assert!(gemini.ends_with(Path::new(".gemini").join("settings.json")));
        assert!(agy.ends_with(Path::new(".gemini").join("config").join("hooks.json")));
    }

    #[test]
    fn installing_backs_up_keeps_a_bom_files_other_settings_and_refuses_a_changed_file() {
        let dir = temp_dir("gemini");
        let path = dir.join(".gemini").join("settings.json");
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        // The way PowerShell 5 writes it: UTF-8 with a BOM.
        let mut original = vec![0xEF, 0xBB, 0xBF];
        original.extend_from_slice(serde_json::to_string(&foreign_gemini()).unwrap().as_bytes());
        std::fs::write(&path, &original).unwrap();

        let shown = preview_at(Agent::Gemini, &path, true).expect("a BOM must not stop the preview");
        assert!(shown.diff.contains(hooks::MARKER), "the diff must show what changes");
        assert!(shown.diff.contains("+ "), "and as added lines");
        assert!(shown.backup.contains("settings.json.bak-"), "{}", shown.backup);
        let backup = write_at(Agent::Gemini, &path, true, &shown.fingerprint).expect("install should succeed");
        assert_eq!(std::fs::read(&backup).unwrap(), original, "the backup holds the original bytes");

        let after: Value = serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
        assert_eq!(after["model"], "gemini-3-pro");
        assert_eq!(after["hooks"]["Notification"], foreign_gemini()["hooks"]["Notification"]);
        assert!(installed_in(Agent::Gemini, &after));
        assert!(status_at(Agent::Gemini, &path).installed);

        // A file that moved since the preview is refused, and left alone.
        let stale = preview_at(Agent::Gemini, &path, false).unwrap();
        std::fs::write(&path, br#"{"model":"someone-else-edited-this"}"#).unwrap();
        let err = write_at(Agent::Gemini, &path, false, &stale.fingerprint).unwrap_err();
        assert!(err.contains("changed since the preview"), "got: {err}");
        assert_eq!(std::fs::read(&path).unwrap(), br#"{"model":"someone-else-edited-this"}"#);

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_file_we_cannot_use_is_refused_before_any_backup_or_write() {
        let dir = temp_dir("refuse");
        let path = dir.join(".gemini").join("settings.json");
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        for (bad, why) in [
            (&b"{ broken"[..], "isn't valid JSON"),
            (&b"[1,2]"[..], "isn't a JSON object"),
            (&br#"{"hooks":[]}"#[..], "unexpected type"),
        ] {
            std::fs::write(&path, bad).unwrap();
            for install in [true, false] {
                let err = preview_at(Agent::Gemini, &path, install).err().expect("a refusal");
                assert!(err.contains(why), "preview: {err}");
                // Even holding the right fingerprint, nothing is written.
                let err = write_at(Agent::Gemini, &path, install, &fingerprint_of(&path)).unwrap_err();
                assert!(err.contains(why), "write: {err}");
                assert_eq!(std::fs::read(&path).unwrap(), bad, "untouched");
                assert_eq!(std::fs::read_dir(path.parent().unwrap()).unwrap().count(), 1, "no backup was taken");
            }
        }
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// A config file that preview would refuse is reported as unreadable, never as "not installed", with the reason in fixed words (never the file's text or its
    /// path): invalid JSON, JSON that is not an object, and (Gemini only) a shape the planner will not merge into (`"hooks"` as a list, one event that is not a
    /// list). A missing file and a valid one are not errors. `preview_at` and `status_at` always agree.
    #[test]
    fn an_unreadable_config_file_says_so_and_a_missing_one_does_not() {
        let dir = temp_dir("status-error");
        let path = dir.join(".gemini").join("settings.json");
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        assert_eq!(status_at(Agent::Gemini, &path).error, None, "no file is not a read error");
        assert_eq!(status_at(Agent::Gemini, &path).reason, None);
        for (bad, reason) in [
            (&b"{ broken"[..], "not valid JSON"),
            (&b"[1,2]"[..], "not an object"),
            (&b"\"x\""[..], "not an object"),
            (&br#"{"hooks":[]}"#[..], "unexpected hooks shape"),
            (&br#"{"hooks":{"BeforeTool":{"not":"a list"}}}"#[..], "unexpected hooks shape"),
        ] {
            std::fs::write(&path, bad).unwrap();
            assert!(preview_at(Agent::Gemini, &path, true).is_err(), "preview refuses {}", String::from_utf8_lossy(bad));
            let broken = status_at(Agent::Gemini, &path);
            assert_eq!(broken.error.as_deref(), Some("Couldn't read the config file."), "{}", String::from_utf8_lossy(bad));
            assert_eq!(broken.reason.as_deref(), Some(reason), "{}", String::from_utf8_lossy(bad));
            let said = format!("{:?} {:?}", broken.error, broken.reason);
            assert!(!said.contains("broken") && !said.contains(&*dir.to_string_lossy()), "no file text, no path in the error or the reason: {said}");
        }
        std::fs::write(&path, br#"{"model":"m"}"#).unwrap();
        assert_eq!(status_at(Agent::Gemini, &path).error, None, "a valid file is no error");
        assert!(preview_at(Agent::Gemini, &path, true).is_ok());
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// Antigravity's hooks.json has its own planner (it merges into anything that is an object), so only a file that cannot be read or is not an object is unusable.
    /// Its status and its preview agree, as Gemini's do.
    #[test]
    fn an_unreadable_antigravity_file_says_so_and_its_preview_agrees() {
        let dir = temp_dir("status-error-agy");
        let path = dir.join(".gemini").join("config").join("hooks.json");
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        for (content, reason) in [(&b"{ broken"[..], Some("not valid JSON")), (&b"[]"[..], Some("not an object")), (&br#"{"hooks":[]}"#[..], None), (&b""[..], None)] {
            std::fs::write(&path, content).unwrap();
            let status = status_at(Agent::Antigravity, &path);
            assert_eq!(status.reason.as_deref(), reason, "{}", String::from_utf8_lossy(content));
            assert_eq!(status.error.is_some(), reason.is_some());
            assert_eq!(preview_at(Agent::Antigravity, &path, true).is_err(), reason.is_some(), "preview agrees with status: {}", String::from_utf8_lossy(content));
        }
        // A folder where the file should be: it cannot be read at all.
        std::fs::remove_file(&path).unwrap();
        std::fs::create_dir(&path).unwrap();
        assert_eq!(status_at(Agent::Antigravity, &path).reason.as_deref(), Some("unreadable"));
        assert!(preview_at(Agent::Antigravity, &path, true).is_err());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_first_install_creates_the_folders_and_a_refusal_creates_nothing() {
        let dir = temp_dir("first");
        let path = dir.join(".gemini").join("config").join("hooks.json");

        // Nothing to remove: say so, and create nothing.
        let err = preview_at(Agent::Antigravity, &path, false).err().expect("a refusal");
        assert_eq!(err, "No Antigravity hooks to remove.");
        assert!(!dir.join(".gemini").exists());

        let shown = preview_at(Agent::Antigravity, &path, true).unwrap();
        assert_eq!(shown.fingerprint, hooks::fingerprint(b""), "a file that is not there is an empty one");
        assert_eq!(shown.backup, "", "there is nothing to back up yet");
        let backup = write_at(Agent::Antigravity, &path, true, &shown.fingerprint).unwrap();
        assert_eq!(backup, "");
        let written: Value = serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
        assert!(installed_in(Agent::Antigravity, &written));
        assert!(written[AGY_KEY].is_object(), "everything is under the notchmeow key");
        assert!(status_at(Agent::Antigravity, &path).installed);

        // And back out again: only our key goes.
        let shown = preview_at(Agent::Antigravity, &path, false).unwrap();
        write_at(Agent::Antigravity, &path, false, &shown.fingerprint).unwrap();
        assert_eq!(serde_json::from_slice::<Value>(&std::fs::read(&path).unwrap()).unwrap(), json!({}));
        assert!(!status_at(Agent::Antigravity, &path).installed);

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn uninstall_with_no_gemini_file_says_so_and_creates_nothing() {
        let dir = temp_dir("nofile");
        let path = dir.join(".gemini").join("settings.json");
        assert_eq!(preview_at(Agent::Gemini, &path, false).err().expect("a refusal"), "No Gemini CLI hooks to remove.");
        assert!(!dir.join(".gemini").exists());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[cfg(unix)]
    #[test]
    fn a_symlinked_config_file_stays_a_symlink_and_its_target_is_updated() {
        let dir = temp_dir("symlink");
        let target = dir.join("dotfiles-settings.json");
        let link = dir.join(".gemini").join("settings.json");
        std::fs::create_dir_all(link.parent().unwrap()).unwrap();
        std::fs::write(&target, br#"{"model":"m"}"#).unwrap();
        std::os::unix::fs::symlink(&target, &link).unwrap();

        let shown = preview_at(Agent::Gemini, &link, true).unwrap();
        write_at(Agent::Gemini, &link, true, &shown.fingerprint).unwrap();

        assert!(std::fs::symlink_metadata(&link).unwrap().file_type().is_symlink(), "the link survives");
        let written: Value = serde_json::from_slice(&std::fs::read(&target).unwrap()).unwrap();
        assert!(installed_in(Agent::Gemini, &written), "the file it points at got the hooks");
        let _ = std::fs::remove_dir_all(&dir);
    }
}
