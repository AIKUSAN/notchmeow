// One chat's Claude Code session: its id, whether it has started, the level the chat is at, and what a level change means.
// Mirrors NotchBuddy/Sources/App/AI/Core/ClaudeChatSession.swift. Pure: `AiState` holds one `ClaudeChat` and `session.rs`
// asks it for each turn.

use crate::ai::claude_cli::Status;
use crate::ai::claude_code::{Level, Platform, Turn};
use crate::ai::provider::Role;

/// What the next turn is: the run to make, whether it needs a recap of the chat so far, and the id that is retired because
/// the session could not be continued.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Plan {
    pub turn: Turn,
    pub needs_recap: bool,
    pub retired: Option<String>,
    /// The folder this turn runs in (what `confirm_started` is told when Claude Code reports the session).
    pub folder: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Session {
    session_id: String,
    /// Claude Code has created the session (it said so in `system/init`): later turns resume it.
    started: bool,
    /// Claude Code keeps a session under the folder it ran in, so it can only be resumed from there.
    started_in: Option<String>,
    /// This session was made in the middle of a chat and has not started yet: every turn that plans it carries the recap,
    /// so a first turn that fails before Claude Code reports the session (and "Try again") is told the chat again.
    needs_recap: bool,
}

/// Where Chat only runs happen: a folder NotchMeow owns and keeps empty (`%APPDATA%\NotchMeow\claude-chat` on Windows).
pub fn chat_folder() -> String {
    crate::settings::config_dir().join("claude-chat").to_string_lossy().to_string()
}

pub fn new_id() -> String {
    // A random version-4 UUID. It is an identifier, not a secret (it is in the process list), so no new crate for it.
    let mut bytes = [0u8; 16];
    #[cfg(unix)]
    {
        use std::io::Read;
        if let Ok(mut f) = std::fs::File::open("/dev/urandom") {
            let _ = f.read_exact(&mut bytes);
        }
    }
    #[cfg(not(unix))]
    {
        // Windows: the hasher's random keys are seeded by the OS for every process and every `RandomState`.
        use std::hash::{BuildHasher, Hasher};
        for chunk in bytes.chunks_mut(8) {
            let mut h = std::collections::hash_map::RandomState::new().build_hasher();
            h.write_u64(std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_nanos() as u64).unwrap_or(0));
            chunk.copy_from_slice(&h.finish().to_le_bytes()[..chunk.len()]);
        }
    }
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    let hex: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
    format!("{}-{}-{}-{}-{}", &hex[0..8], &hex[8..12], &hex[12..16], &hex[16..20], &hex[20..32])
}

impl Default for Session {
    fn default() -> Self {
        Session::with_id(new_id())
    }
}

impl Session {
    pub fn with_id(session_id: String) -> Self {
        Session { session_id, started: false, started_in: None, needs_recap: false }
    }

    pub fn id(&self) -> &str {
        &self.session_id
    }

    /// The next turn. A level change that keeps the working folder resumes the same session with the new flags. One that
    /// moves it (Agent in a project, then Chat only) starts a new session, to be seeded with a recap, and retires the old
    /// id: Claude Code could not find the old session from the new folder, and a late approval request from it must be
    /// refused.
    pub fn plan(&mut self, level: &Level, model: &str, chat_folder: &str, platform: Platform, new_id: impl FnOnce() -> String) -> Plan {
        let folder = level.folder().unwrap_or(chat_folder).to_string();
        let mut retired = None;
        if self.started && self.started_in.as_deref() != Some(folder.as_str()) {
            retired = Some(std::mem::replace(&mut self.session_id, new_id()));
            self.started = false;
            self.started_in = None;
            self.needs_recap = true;
        }
        let turn = Turn { level: level.clone(), model: model.to_string(), session_id: self.session_id.clone(), resume: self.started, platform };
        Plan { turn, needs_recap: self.needs_recap, retired, folder }
    }

    /// The chat's history was loaded from a file: a session that has not started is told that history, on its first turn.
    pub fn reseed(&mut self) {
        if !self.started {
            self.needs_recap = true;
        }
    }

    /// Claude Code reported the session: the next turn resumes it.
    pub fn confirm_started(&mut self, folder: &str) {
        self.started = true;
        self.started_in = Some(folder.to_string());
        self.needs_recap = false;
    }

    /// A new conversation: the old id is returned so it can be retired, and nothing of it is kept.
    pub fn reset(&mut self, new_id: impl FnOnce() -> String) -> String {
        std::mem::replace(self, Session::with_id(new_id())).session_id
    }

    /// A run of this session was refused for its tools and killed right after `init`, so Claude Code may have recorded it:
    /// a fresh session takes its place, told the chat so far.
    fn refused(&mut self, new_id: impl FnOnce() -> String) {
        *self = Session { needs_recap: true, ..Session::with_id(new_id()) };
    }
}

/// The chat's side of Claude Code: its session, its level, and what the last check found.
#[derive(Debug, Clone)]
pub struct ClaudeChat {
    pub session: Session,
    pub level: Level,
    pub status: Status,
    /// Where Chat only runs. `None` is `chat_folder()`; a test points it at a folder of its own.
    pub chat_folder: Option<String>,
    /// Memory only: set by a quick Explain that started this chat. While set, every Claude turn of the chat runs at `NoTools`,
    /// until a level is picked, the chat is cleared or another conversation is opened.
    pub quick_hold: bool,
}

impl Default for ClaudeChat {
    fn default() -> Self {
        ClaudeChat { session: Session::default(), level: Level::ChatOnly, status: Status::not_installed(), chat_folder: None, quick_hold: false }
    }
}

impl ClaudeChat {
    /// A run reported its session. Only the chat's current session is confirmed: a run that was still going when the chat
    /// was cleared belongs to a retired id, and must not make the new session look started (the next turn would resume a
    /// session Claude Code never made).
    pub fn confirm(&mut self, session_id: &str, folder: &str) -> bool {
        let current = self.session.id() == session_id;
        if current {
            self.session.confirm_started(folder);
        }
        current
    }

    /// A run of `session_id` was refused for its tools: only the chat's current session is retired (a run of an older one
    /// has nothing to take away). Level and hold are the picker's to change, not the refusal's.
    pub fn refuse(&mut self, session_id: &str) -> bool {
        let current = self.session.id() == session_id;
        if current {
            self.session.refused(new_id);
        }
        current
    }

    /// A level picked in the picker. Any pick ends the quick hold; it applies from the next turn.
    pub fn set_level(&mut self, level: Level) {
        self.level = level;
        self.quick_hold = false;
    }

    /// A new conversation starts at Chat only, on a new session, with no quick hold. Returns the id that was retired.
    pub fn reset(&mut self) -> String {
        self.level = Level::ChatOnly;
        self.quick_hold = false;
        self.session.reset(new_id)
    }
}

const RECAP_MAX_TURNS: usize = 20;
const RECAP_MAX_TURN_CHARS: usize = 1_500;
const RECAP_MAX_CHARS: usize = 20_000;

/// A recap of the chat so far, for a session started afresh in the middle of it. `None` when there is nothing to recall.
/// Oldest turns go first when it is too long. Only the words are kept (no file bodies).
pub fn recap(turns: &[(Role, String)]) -> Option<String> {
    let skip = turns.len().saturating_sub(RECAP_MAX_TURNS);
    let mut lines: Vec<String> = turns[skip..]
        .iter()
        .filter_map(|(role, text)| {
            let words = text.trim();
            if words.is_empty() {
                return None;
            }
            let cut = if words.chars().count() > RECAP_MAX_TURN_CHARS {
                format!("{}…", words.chars().take(RECAP_MAX_TURN_CHARS).collect::<String>())
            } else {
                words.to_string()
            };
            Some(format!("{}{cut}", if *role == Role::User { "User: " } else { "Assistant: " }))
        })
        .collect();
    while lines.join("\n").chars().count() > RECAP_MAX_CHARS && lines.len() > 1 {
        lines.remove(0);
    }
    (!lines.is_empty()).then(|| format!("Earlier in this chat, for context only (it is already answered):\n{}", lines.join("\n")))
}

#[cfg(test)]
mod tests {
    use super::*;

    const CHAT: &str = "/support/NotchMeow/claude-chat";

    fn ids() -> impl FnMut() -> String {
        let mut n = 0;
        move || {
            n += 1;
            format!("id-{n}")
        }
    }

    #[test]
    fn a_chats_session() {
        let mut next = ids();
        let mut chat = Session::with_id(next());
        let first = chat.plan(&Level::ChatOnly, "sonnet", CHAT, Platform::Linux, &mut next);
        assert_eq!((first.turn.level.clone(), first.turn.resume, first.needs_recap, first.turn.session_id.as_str()), (Level::ChatOnly, false, false, "id-1"));

        let mut again = chat.clone();
        assert!(!again.plan(&Level::ChatOnly, "sonnet", CHAT, Platform::Linux, &mut next).turn.resume, "a turn that never reached init is planned the same way");

        chat.confirm_started(CHAT);
        assert!(chat.plan(&Level::ChatOnly, "sonnet", CHAT, Platform::Linux, &mut next).turn.resume, "after init the next turn resumes");

        let project = "/home/zoe/projects/notchmeow";
        let moved = chat.plan(&Level::ReadOnly(project.into()), "sonnet", CHAT, Platform::Linux, &mut next);
        assert_eq!((moved.turn.session_id.as_str(), moved.turn.resume, moved.needs_recap), ("id-2", false, true), "a level change that moves the working folder starts a new session");
        assert_eq!(moved.retired.as_deref(), Some("id-1"), "and retires the old one");
        chat.confirm_started(project);

        let kept = chat.plan(&Level::Agent(project.into()), "sonnet", CHAT, Platform::Linux, &mut next);
        assert_eq!((kept.turn.session_id.as_str(), kept.turn.resume, kept.needs_recap, kept.retired), ("id-2", true, false, None), "Read-only to Agent in the same folder resumes the session");
        assert_eq!(kept.turn.level, Level::Agent(project.into()), "with the new flags");

        let back = chat.plan(&Level::ChatOnly, "sonnet", CHAT, Platform::Linux, &mut next);
        assert_eq!((back.turn.session_id.as_str(), back.needs_recap, back.retired.as_deref()), ("id-3", true, Some("id-2")), "Agent back to Chat only moves it again");

        let mut reset = chat.clone();
        assert_eq!(reset.reset(|| "id-9".into()), "id-3");
        assert_eq!((reset.id(), reset.started), ("id-9", false), "a new conversation retires the id and starts clean");
    }

    #[test]
    fn the_recap_is_kept_until_the_session_has_started() {
        let mut next = ids();
        let mut chat = Session::with_id(next());
        chat.plan(&Level::ChatOnly, "sonnet", CHAT, Platform::Linux, &mut next);
        chat.confirm_started(CHAT);
        let project = "/home/zoe/projects/notchmeow";
        let moved = chat.plan(&Level::ReadOnly(project.into()), "sonnet", CHAT, Platform::Linux, &mut next);
        assert_eq!((moved.needs_recap, moved.retired.as_deref()), (true, Some("id-1")));

        // The first turn of the new session failed before Claude Code reported it, and the user tries again.
        let retry = chat.plan(&Level::ReadOnly(project.into()), "sonnet", CHAT, Platform::Linux, &mut next);
        assert_eq!((retry.turn.session_id.as_str(), retry.turn.resume, retry.needs_recap, retry.retired), ("id-2", false, true, None), "the same new session, still told the chat so far, and nothing retired twice");
        // Even after the user moved the level again before it ever started.
        assert!(chat.plan(&Level::ChatOnly, "sonnet", CHAT, Platform::Linux, &mut next).needs_recap);

        chat.confirm_started(CHAT);
        assert!(!chat.plan(&Level::ChatOnly, "sonnet", CHAT, Platform::Linux, &mut next).needs_recap, "once it has started, the recap is spent");
    }

    #[test]
    fn a_reseeded_session_plans_a_recap_and_no_resume() {
        let mut next = ids();
        let mut chat = Session::with_id(next());
        chat.reseed();
        let plan = chat.plan(&Level::ChatOnly, "sonnet", CHAT, Platform::Linux, &mut next);
        assert_eq!((plan.turn.resume, plan.needs_recap, plan.retired), (false, true, None), "a loaded chat's session is told the chat so far");
        chat.confirm_started(CHAT);
        chat.reseed();
        assert!(!chat.plan(&Level::ChatOnly, "sonnet", CHAT, Platform::Linux, &mut next).needs_recap, "a session that has started is never reseeded");
    }

    #[test]
    fn a_real_id_is_a_lower_case_version_4_uuid() {
        for _ in 0..3 {
            let id = new_id();
            let parts: Vec<&str> = id.split('-').collect();
            assert_eq!(parts.iter().map(|p| p.len()).collect::<Vec<_>>(), [8, 4, 4, 4, 12], "{id}");
            assert!(id.chars().all(|c| c == '-' || c.is_ascii_hexdigit() && !c.is_ascii_uppercase()), "{id}");
            assert!(parts[2].starts_with('4') && "89ab".contains(&parts[3][..1]), "{id}");
        }
        assert_ne!(new_id(), new_id());
    }

    #[test]
    fn a_run_that_was_reset_away_cannot_start_the_new_session() {
        let mut chat = ClaudeChat::default();
        let old = chat.session.id().to_string();
        chat.reset();
        assert!(!chat.confirm(&old, CHAT), "the old run reported its session after the chat was cleared");
        assert!(!chat.session.plan(&Level::ChatOnly, "sonnet", CHAT, Platform::Linux, new_id).turn.resume, "the new session was never made, so it is not resumed");
        let current = chat.session.id().to_string();
        assert!(chat.confirm(&current, CHAT));
        assert!(chat.session.plan(&Level::ChatOnly, "sonnet", CHAT, Platform::Linux, new_id).turn.resume);
    }

    /// A run refused for its tools was killed right after `init`: Claude Code may have recorded that session, so it is
    /// never planned again (`--session-id` on a recorded id, or `--resume` on an empty one).
    #[test]
    fn a_refused_run_retires_the_session_and_the_next_one_is_told_the_chat() {
        let mut chat = ClaudeChat { quick_hold: true, ..ClaudeChat::default() };
        let old = chat.session.id().to_string();
        assert!(chat.confirm(&old, CHAT), "an earlier turn had started it");
        assert!(chat.refuse(&old));
        let next = chat.session.plan(&Level::ChatOnly, "sonnet", CHAT, Platform::Linux, new_id);
        assert_ne!(next.turn.session_id, old, "a fresh id");
        assert!(!next.turn.resume && next.needs_recap, "a fresh session, told the chat so far");
        assert!(chat.quick_hold, "the hold is not the refusal's to end");
        assert!(!chat.refuse(&old), "a refused run of a retired id leaves the current session alone");
    }

    #[test]
    fn a_new_chat_starts_at_chat_only() {
        let mut chat = ClaudeChat::default();
        chat.level = Level::Agent("/x".into());
        let old = chat.session.id().to_string();
        assert_eq!(chat.reset(), old);
        assert_eq!(chat.level, Level::ChatOnly);
        assert_ne!(chat.session.id(), old);
    }

    #[test]
    fn the_recap_of_a_chat() {
        assert_eq!(recap(&[]), None, "nothing to recall");
        let text = recap(&[(Role::User, "What is in main.rs?".into()), (Role::Assistant, "A greeting.".into()), (Role::User, "  ".into()), (Role::User, "Thanks".into())]).unwrap();
        assert_eq!(text.lines().skip(1).collect::<Vec<_>>(), ["User: What is in main.rs?", "Assistant: A greeting.", "User: Thanks"], "the words, in order, with who said them");
        assert!(recap(&[(Role::User, "x".repeat(5000))]).unwrap().chars().count() < 1700, "a long turn is cut");
        let many: Vec<(Role, String)> = (0..60).map(|i| (Role::User, format!("message {i} {}", "y".repeat(1200)))).collect();
        let recent = recap(&many).unwrap();
        assert!(recent.chars().count() <= RECAP_MAX_CHARS + 200 && recent.contains("message 59") && !recent.contains("message 0 "), "only the most recent turns, within the budget");
    }
}
