// Preferences, stored as plain JSON in settings.json under platform::config_dir().
// No secret ever lands here — API keys live in the OS keychain (see secrets.rs).

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;

use serde::{Deserialize, Serialize};

use crate::ai::router::{Choice, ModelRef};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Settings {
    pub sound_enabled: bool,
    pub sound_volume: f64,
    pub auto_close_interval: f64,
    /// Hovering the island opens it all the way (off: hovering only peeks).
    #[serde(default)]
    pub open_on_hover: bool,
    /// A soft rainbow halo along the island's outline while the pointer is over it (on by default).
    #[serde(default = "default_true")]
    pub hover_glow: bool,
    /// Step back when I'm already in the app (focus awareness): a permission request whose app is in front is declined at once so the agent asks there (on by default). A value that is not a Boolean reads as on.
    #[serde(default = "default_true", deserialize_with = "bool_or_true")]
    pub focus_aware: bool,
    /// When the compact island hides by itself: "never" (the default), or "1", "5", "15" or "30" minutes of quiet once nothing is live (island/tuckaway.ts, as on the Mac).
    /// Cleaned by `clean_tuck_away` on load and on save.
    #[serde(default = "default_tuck_away")]
    pub tuck_away: String,
    pub active_integrations: Vec<String>,
    /// "primary" = the main display, "cursor" = whichever display the mouse is on.
    pub screen: String,
    pub autostart: bool,
    pub hooks_installed: bool,
    /// Up to 0.1.1 the chat had a single Claude model here. `load` moves it into
    /// `ai.cloud_models["anthropic"]`; it is never written back.
    #[serde(default, skip_serializing)]
    pub model: Option<String>,
    /// Which models answer. Defaulted so a settings.json from an older build still loads.
    #[serde(default)]
    pub ai: AiSettings,
    /// The Cat section of Settings (spec §4), its Display settings (sub-project B) and the desktop cat's (sub-project H, `desktop: {on, size, spots}`): `{character, motionStyle, collar, furLines, cats, displayMode, pair,
    /// agentCats}`. Held as a JSON value, never as a typed struct, so that one bad field cannot fail the whole file; `sanitized` runs it through
    /// `cat_settings::clean_cat_block`, which cleans both parts (cleaning the Cat settings alone would drop the three display keys at the next save).
    #[serde(default = "crate::cat_settings::block_default")]
    pub cat: serde_json::Value,
    /// The Sidekick settings (sub-project F1): `{on, local, dismissals}`. Held as a JSON value, like `cat`, so that one bad field cannot fail the whole file; `sanitized` runs
    /// it through `sidekick_settings::clean_sidekick` on load and on every save, and a file from before F1 gets everything on and nothing dismissed.
    #[serde(default = "crate::sidekick_settings::default_value")]
    pub sidekick: serde_json::Value,
    /// The Companion settings (sub-project F3a): `{humor, useMemory, seeSessions, polishRecap, recapDismissals, lastRecapDay, cloudNoticeShown}`. Held as a JSON value, like
    /// `sidekick`, so that one bad field cannot fail the file; `sanitized` runs it through `companion_settings::clean_companion` on load and on every save.
    #[serde(default = "crate::companion_settings::default_value")]
    pub companion: serde_json::Value,
}

/// The AI part of settings.json (spec §4). Keys are never here: they live in the
/// OS keychain (secrets.rs).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct AiSettings {
    /// Which model answers in the chat: "auto" or {provider, model}.
    pub chat: Choice,
    /// Which model answers questions about a dropped file.
    pub files: Choice,
    /// "claudeCode", "anthropic" or "openai": the cloud Auto tries first.
    pub preferred_cloud: String,
    /// Remembered model per cloud provider, e.g. {"anthropic": "claude-opus-5"}.
    pub cloud_models: BTreeMap<String, String>,
    /// Last-used model per local server, e.g. {"ollama": "qwen3.5:2b"}.
    pub local_models: BTreeMap<String, String>,
    /// The local model Auto uses first when there is no cloud key.
    pub last_used_local: Option<ModelRef>,
    /// The server added with "Add server…", e.g. "http://studio-pc:11434".
    pub custom_server: Option<String>,
    /// The user connected "Use my Claude plan": Auto may use it while the last check finds Claude Code signed in.
    pub claude_code_enabled: bool,
    /// Claude Code's model alias for the chat: sonnet, opus or haiku.
    pub claude_code_model: String,
}

impl Default for AiSettings {
    fn default() -> Self {
        AiSettings {
            chat: Choice::default(),
            files: Choice::default(),
            preferred_cloud: "anthropic".into(),
            cloud_models: BTreeMap::new(),
            local_models: BTreeMap::new(),
            last_used_local: None,
            custom_server: None,
            claude_code_enabled: false,
            claude_code_model: "sonnet".into(),
        }
    }
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            sound_enabled: true,
            sound_volume: 0.12,
            auto_close_interval: 15.0,
            open_on_hover: false,
            hover_glow: true,
            focus_aware: true,
            tuck_away: default_tuck_away(),
            active_integrations: vec![
                "integration_resend".into(),
                "integration_n8n".into(),
                "integration_vercel".into(),
                "integration_github".into(),
            ],
            screen: "primary".into(),
            autostart: false,
            hooks_installed: false,
            model: None,
            ai: AiSettings::default(),
            cat: crate::cat_settings::block_default(),
            sidekick: crate::sidekick_settings::default_value(),
            companion: crate::companion_settings::default_value(),
        }
    }
}

fn default_true() -> bool {
    true
}

/// A Boolean as stored; anything else (a string, null, a number) reads as on, so one odd value never fails the whole file.
fn bool_or_true<'de, D: serde::Deserializer<'de>>(d: D) -> Result<bool, D::Error> {
    Ok(serde_json::Value::deserialize(d)?.as_bool().unwrap_or(true))
}

fn default_tuck_away() -> String {
    "never".into()
}

/// The stored tuck-away choice: "never", "1", "5", "15" or "30"; anything else reads as "never" (the Mac's `IslandTuckAway.choice(stored:)`).
pub fn clean_tuck_away(stored: &str) -> String {
    match stored {
        "1" | "5" | "15" | "30" => stored.to_string(),
        _ => "never".to_string(),
    }
}

pub use crate::platform::{config_dir, local_dir};

pub fn hook_exe_path() -> PathBuf {
    local_dir().join("bin").join(crate::platform::HOOK_EXE)
}

fn settings_path() -> PathBuf {
    config_dir().join("settings.json")
}

/// What stopped the settings file from loading. The page reads it at boot (`BootInfo.settings_problem`) as `{ kind, keptAs }`. It names a file, never a
/// path or any content.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(tag = "kind", rename_all = "lowercase")]
pub enum LoadProblem {
    /// The file is there but cannot be read: defaults are in use and saves are refused until the user chooses (Try again, or Start fresh).
    Unreadable,
    /// The file did not parse. `kept_as` is the copy's file name; it is empty only when a read-only read found the file in place and kept nothing.
    /// Defaults are in use; saves go on, because a copy exists (or the file is not ours to move).
    Unparseable {
        #[serde(rename = "keptAs")]
        kept_as: String,
    },
}

/// Set while the file is unreadable, so nothing is written over a file that was never read. Set at start-up; Start fresh and a successful Try again clear it.
static SAVE_BLOCKED: AtomicBool = AtomicBool::new(false);

/// The UTF-8 byte order mark (Notepad's "UTF-8 with BOM"): not JSON, so it is taken off before the file is parsed.
const BOM: &[u8] = &[0xEF, 0xBB, 0xBF];

/// The file as the app starts with it, and what stopped it loading. A file that does not parse is moved aside as a backup (copied when it cannot be moved). When
/// neither works it stays in place and is `Unreadable`: the next save would write over it. A missing file is the first run, not a problem.
pub fn load_checked() -> (Settings, Option<LoadProblem>) {
    load_checked_with(&settings_path(), |from: &Path, to: &Path| std::fs::rename(from, to), |from: &Path, to: &Path| std::fs::copy(from, to))
}

/// The file as it is now, nothing moved or copied, for Try again and Start fresh. A file that does not parse is `Unreadable` here, as at boot when no backup
/// could be kept: it is still in place, and a save must not write over it. A retry (or a start fresh) never adds a backup.
pub fn load_checked_read_only() -> (Settings, Option<LoadProblem>) {
    read_only_at(&settings_path())
}

/// Only an unreadable file refuses saves. A file that did not parse was kept as a backup, so saving over it is safe.
pub fn save_allowed(problem: &Option<LoadProblem>) -> bool {
    !matches!(problem, Some(LoadProblem::Unreadable))
}

/// The words Start fresh answers with when it does not clear the refusal.
const START_FRESH_MISSING: &str = "There is no settings file to replace; use Try again.";
const START_FRESH_READS: &str = "Your settings file can be read now; use Try again.";
const START_FRESH_STILL: &str = "Your settings file still couldn't be read.";

/// Start fresh clears the refusal only when the file was unreadable at boot (`current`) and still cannot be read now (`now`, the read-only load). Otherwise it says
/// why: the file is missing, it reads now, or it still cannot be read. `present` is whether a file (or a folder in its place) is there.
pub fn start_fresh_refusal(current: &Option<LoadProblem>, now: &Option<LoadProblem>, present: bool) -> Option<&'static str> {
    if matches!(current, Some(LoadProblem::Unreadable)) && matches!(now, Some(LoadProblem::Unreadable)) {
        return None;
    }
    if now.is_some() {
        return Some(START_FRESH_STILL);
    }
    Some(if present { START_FRESH_READS } else { START_FRESH_MISSING })
}

/// Whether the settings file is in place, for Start fresh's words.
pub fn settings_file_exists() -> bool {
    settings_path().exists()
}

/// Sets the save gate from the problem the file has now.
pub fn set_save_gate(problem: &Option<LoadProblem>) {
    SAVE_BLOCKED.store(!save_allowed(problem), Ordering::SeqCst);
}

/// What the file holds, read in place: nothing is moved, copied or written here.
enum FileRead {
    Missing,
    Unreadable,
    Broken,
    Parsed(Settings),
}

fn read_file(path: &Path) -> FileRead {
    let bytes = match std::fs::read(path) {
        Ok(bytes) => bytes,
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => return FileRead::Missing,
        Err(_) => return FileRead::Unreadable,
    };
    let json = bytes.strip_prefix(BOM).unwrap_or(&bytes[..]);
    match serde_json::from_slice(json) {
        Ok(parsed) => FileRead::Parsed(sanitized(migrate(parsed))),
        Err(_) => FileRead::Broken,
    }
}

/// Defaults in use, and saves refused: the file is there and cannot be used as it is.
fn unreadable() -> (Settings, Option<LoadProblem>) {
    (Settings::default(), Some(LoadProblem::Unreadable))
}

fn read_only_at(path: &Path) -> (Settings, Option<LoadProblem>) {
    match read_file(path) {
        FileRead::Missing => (Settings::default(), None),
        FileRead::Parsed(s) => (s, None),
        FileRead::Unreadable => {
            crate::log::line("settings.json could not be read; defaults are in use and nothing is saved until the user chooses");
            unreadable()
        }
        FileRead::Broken => {
            crate::log::line("settings.json is not valid JSON; defaults are in use and nothing is saved until the user chooses");
            unreadable()
        }
    }
}

/// A file that doesn't parse (a hand-edit slip) is renamed to `settings.json.bad-<stamp>` and defaults are used, so the next save can't wipe what the user
/// typed. The log names the backup, never the content. A file that cannot be read at all, or cannot be kept, is `Unreadable`.
/// The two file operations are parameters so a test can make them fail.
fn load_checked_with(
    path: &Path,
    move_aside: impl Fn(&Path, &Path) -> std::io::Result<()>,
    copy_aside: impl Fn(&Path, &Path) -> std::io::Result<u64>,
) -> (Settings, Option<LoadProblem>) {
    match read_file(path) {
        FileRead::Missing => (Settings::default(), None),
        FileRead::Parsed(s) => (s, None),
        FileRead::Unreadable => {
            crate::log::line("settings.json could not be read; defaults are in use and nothing is saved until the user chooses");
            unreadable()
        }
        FileRead::Broken => {
            let bad = path.with_file_name(format!("settings.json.bad-{}", crate::hooks::stamp()));
            let name = bad.file_name().and_then(|n| n.to_str()).unwrap_or("settings.json.bad").to_string();
            // Moving can fail (permissions, a locked file): copy instead, and say so either way. A copy that failed part-way is removed.
            // Names only, never content.
            let kept = if move_aside(path, &bad).is_ok() {
                crate::log::line(format!("settings.json did not parse; kept as {name}"));
                true
            } else if copy_aside(path, &bad).is_ok() {
                crate::log::line(format!("settings.json did not parse; could not move it, copied to {name}"));
                true
            } else {
                let _ = std::fs::remove_file(&bad);
                crate::log::line(format!("settings.json did not parse; could not keep a backup ({name})"));
                false
            };
            // With no backup the file is still there, and the next save would write over it: that is a file that cannot be read.
            let problem = if kept { LoadProblem::Unparseable { kept_as: name } } else { LoadProblem::Unreadable };
            (Settings::default(), Some(problem))
        }
    }
}

/// What may be kept and shown: the server the user added loses a typed `user:pass@` (and any
/// query), because settings.json is plain text and the webview sees it; the Cat block is
/// cleaned to its 16 cats and its frozen words. Applied on load and to everything the webview
/// saves; the server's key lives in the keychain, never in a URL.
pub fn sanitized(mut settings: Settings) -> Settings {
    settings.ai.custom_server = settings.ai.custom_server.as_deref().and_then(crate::ai::discovery::clean_server_url);
    settings.ai.claude_code_model = crate::ai::claude_code::model_or_default(&settings.ai.claude_code_model);
    settings.tuck_away = clean_tuck_away(&settings.tuck_away);
    settings.cat = crate::cat_settings::clean_cat_block(&settings.cat);
    settings.sidekick = crate::sidekick_settings::clean_sidekick(&settings.sidekick);
    settings.companion = crate::companion_settings::clean_companion(&settings.companion);
    settings
}

/// Moves the pre-AI `model` (a Claude model id) into the AI settings, once.
pub fn migrate(mut settings: Settings) -> Settings {
    if let Some(model) = settings.model.take() {
        settings.ai.cloud_models.entry("anthropic".into()).or_insert(model);
    }
    for choice in [&mut settings.ai.chat, &mut settings.ai.files] {
        keep_old_default(choice);
    }
    settings
}

/// Before E1 a local or Google model was stored only when it wasn't the default, so a provider
/// without a model is a deliberate choice of that default: it never becomes Auto, which could
/// use the cloud. A provider with no such default has nothing to keep and goes back to Auto.
fn keep_old_default(choice: &mut Choice) {
    let Choice::Explicit(m) = choice else { return };
    if !m.model.is_empty() {
        return;
    }
    match m.provider.as_str() {
        "ollama" => m.model = "llama3.2".into(),
        "lmstudio" => m.model = "local-model".into(),
        "google" => m.model = "gemini-2.0-flash".into(),
        _ => *choice = Choice::default(),
    }
}

/// Every writer comes through here, so the gate covers the window's saves, the hooks' and the AI's. Its callers, each holding `shared.settings` (through
/// `commit` or `update`) while it writes: `lib.rs` `save_settings` (commit), `lib.rs` `hooks_apply` (update), `ai/mod.rs` `store_learned` (update). The link's
/// own settings file has its own `save` in `link/settings.rs`.
pub fn save(settings: &Settings) -> std::io::Result<()> {
    save_with(&SAVE_BLOCKED, &settings_path(), settings, rename_over)
}

/// The rename a save uses. A named fn, because `std::fs::rename` itself does not satisfy the seam's higher-ranked `Fn(&Path, &Path)` bound.
fn rename_over(from: &Path, to: &Path) -> std::io::Result<()> {
    std::fs::rename(from, to)
}

/// Written beside the file and renamed over it, as hooks.rs and shelf.rs do: a process that dies or a full disk leaves the old file whole, never half of a new one that
/// would then fail to parse. The temp's data is flushed before the rename, so after a power loss the folder holds the old file or the new one, not an empty one.
/// A temp that could not be written or renamed is removed. The gate and the rename are parameters, so a test can run both.
///
/// A symlink (a dotfiles setup) is followed to its target, which is written; the link stays. The file keeps the mode it had (a new file gets the default), and one
/// the user made read-only (unix: no owner write bit) is refused, as the old plain write refused it. The links are settled first, so a loop touches nothing.
/// `ensure_private_dir` runs on the path's own folder only, never on a link target's folder (on Linux it sets 0700). The temp name carries the pid: safe
/// because every caller holds `shared.settings` while it writes (see `save`), so two saves in this process never share a temp.
fn save_with(blocked: &AtomicBool, path: &Path, settings: &Settings, rename: impl Fn(&Path, &Path) -> std::io::Result<()>) -> std::io::Result<()> {
    if blocked.load(Ordering::SeqCst) {
        return Err(std::io::Error::other("settings.json could not be read, so nothing is written until the user chooses"));
    }
    let target = settle_target(path)?;
    let json = serde_json::to_vec_pretty(settings)
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;
    refuse_read_only(&target)?;
    if let Some(dir) = path.parent() {
        crate::platform::ensure_private_dir(dir)?;
    }
    let temp = target.with_extension(format!("json.notchmeow-{}", std::process::id()));
    let written = write_temp(&temp, &target, &json).and_then(|_| rename(&temp, &target));
    if written.is_err() {
        let _ = std::fs::remove_file(&temp);
    }
    written
}

/// A file with no owner write bit is the user's way of saying "don't change this": the rename would go round it. (Windows refuses to rename over a read-only file itself.)
#[cfg(unix)]
fn refuse_read_only(target: &Path) -> std::io::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    match std::fs::metadata(target) {
        Ok(meta) if meta.permissions().mode() & 0o200 == 0 => Err(std::io::Error::from(std::io::ErrorKind::PermissionDenied)),
        _ => Ok(()),
    }
}

#[cfg(not(unix))]
fn refuse_read_only(_target: &Path) -> std::io::Result<()> {
    Ok(())
}

/// The file a save writes. On unix each link is followed one hop at a time, so a link whose target is missing (dangling) is written through and not replaced;
/// a loop of links is an error, and nothing is touched.
#[cfg(unix)]
fn settle_target(path: &Path) -> std::io::Result<PathBuf> {
    let mut here = path.to_path_buf();
    for _ in 0..40 {
        match std::fs::symlink_metadata(&here) {
            Ok(meta) if meta.file_type().is_symlink() => {
                let link = std::fs::read_link(&here)?;
                here = if link.is_absolute() { link } else { here.parent().unwrap_or(Path::new(".")).join(link) };
            }
            Ok(_) => return Ok(here),
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => return Ok(here),
            Err(err) => return Err(err),
        }
    }
    Err(std::io::Error::other("the settings file's links go round in a loop"))
}

#[cfg(not(unix))]
fn settle_target(path: &Path) -> std::io::Result<PathBuf> {
    Ok(path.to_path_buf())
}

/// Writes `json` to `temp`, which is about to replace `target`. On unix the temp is created with the target's mode (so the content is never in a wider file),
/// the exact mode is set after the write (the umask cannot narrow it), and a new file gets the default. A stale temp of this name is removed first, and
/// `create_new` never follows a link planted at the name.
#[cfg(unix)]
fn write_temp(temp: &Path, target: &Path, json: &[u8]) -> std::io::Result<()> {
    use std::io::Write;
    use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
    let original = std::fs::metadata(target).ok().map(|m| m.permissions().mode() & 0o777);
    let _ = std::fs::remove_file(temp);
    let mut file = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(original.unwrap_or(0o666))
        .open(temp)?;
    file.write_all(json)?;
    if let Some(mode) = original {
        file.set_permissions(std::fs::Permissions::from_mode(mode))?;
    }
    file.sync_all()
}

#[cfg(not(unix))]
fn write_temp(temp: &Path, _target: &Path, json: &[u8]) -> std::io::Result<()> {
    use std::io::Write;
    let _ = std::fs::remove_file(temp);
    let mut file = std::fs::OpenOptions::new().write(true).create_new(true).open(temp)?;
    file.write_all(json)?;
    file.sync_all()
}

/// The words a save is refused with. Fixed sentences: no path, no system text (the log has the same, with the error kind).
pub const AUTOSTART_REFUSED: &str = "Couldn't change Launch at startup. Nothing was saved.";
pub const SAVE_REFUSED: &str = "Couldn't save the settings.";

/// A save that changes "Launch at startup", in the order that keeps the system and the file in step: the system first, so a refusal writes nothing and is told;
/// then the file, and when it refuses the startup change is put back (best effort, logged when it too is refused). `set_startup` says whether the system took
/// the change. `was` and `wanted` are the stored and the new value, and nothing is asked of the system when they match.
pub fn save_in_step<T>(
    was: bool,
    wanted: bool,
    set_startup: impl Fn(bool) -> bool,
    write: impl FnOnce() -> std::io::Result<T>,
) -> Result<T, &'static str> {
    let changes_startup = was != wanted;
    if changes_startup && !set_startup(wanted) {
        crate::log::line("Launch at startup could not be changed");
        return Err(AUTOSTART_REFUSED);
    }
    write().map_err(|err| {
        crate::log::line(format!("settings.json could not be saved ({:?})", err.kind()));
        if changes_startup && !set_startup(was) {
            crate::log::line("Launch at startup could not be put back");
        }
        SAVE_REFUSED
    })
}

/// The write comes first: `next` replaces the shared copy only when `write` (the file) succeeds, and the replaced value comes back so the caller can see what changed.
/// The lock is held across the write, so two saves reach the file in the order they reach the shared copy.
pub fn commit(current: &Mutex<Settings>, next: Settings, write: impl Fn(&Settings) -> std::io::Result<()>) -> std::io::Result<Settings> {
    let mut held = current.lock().unwrap();
    write(&next)?;
    Ok(std::mem::replace(&mut *held, next))
}

/// A change made to the shared copy under one lock, the same write-first rule as `commit`: `change` edits a copy and says whether anything changed. Nothing changed
/// means nothing is written and `None`; otherwise the file is written and, only if that works, the copy is replaced and returned. The lock covers the read as well,
/// so a save that lands in between is not lost.
pub fn update(current: &Mutex<Settings>, change: impl FnOnce(&mut Settings) -> bool, write: impl Fn(&Settings) -> std::io::Result<()>) -> std::io::Result<Option<Settings>> {
    let mut held = current.lock().unwrap();
    let mut next = held.clone();
    if !change(&mut next) {
        return Ok(None);
    }
    write(&next)?;
    *held = next.clone();
    Ok(Some(next))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn checked(path: &Path) -> (Settings, Option<LoadProblem>) {
        load_checked_with(path, |from: &Path, to: &Path| std::fs::rename(from, to), |from: &Path, to: &Path| std::fs::copy(from, to))
    }

    #[test]
    fn a_settings_file_without_hover_glow_gets_it_on_and_keeps_it_when_turned_off() {
        let old = r#"{"soundEnabled":true,"soundVolume":0.12,"autoCloseInterval":15,"absenceInterval":180,
            "activeIntegrations":[],"screen":"primary","autostart":false,"hooksInstalled":false}"#;
        let s: Settings = serde_json::from_str(old).unwrap();
        assert!(s.hover_glow);
        assert_eq!(serde_json::to_value(&s).unwrap()["hoverGlow"], true);
        let off: Settings = serde_json::from_str(&old.replace("\"autostart\"", "\"hoverGlow\":false,\"autostart\"")).unwrap();
        assert!(!off.hover_glow);
    }

    #[test]
    fn a_settings_file_without_open_on_hover_gets_it_off_and_keeps_it_when_set() {
        let old = r#"{"soundEnabled":true,"soundVolume":0.12,"autoCloseInterval":15,"absenceInterval":180,
            "activeIntegrations":[],"screen":"primary","autostart":false,"hooksInstalled":false}"#;
        let s: Settings = serde_json::from_str(old).unwrap();
        assert!(!s.open_on_hover);
        assert_eq!(serde_json::to_value(&s).unwrap()["openOnHover"], false);
        let on: Settings = serde_json::from_str(&old.replace("\"autostart\"", "\"openOnHover\":true,\"autostart\"")).unwrap();
        assert!(on.open_on_hover);
    }

    #[test]
    fn a_settings_file_without_focus_aware_gets_it_on_and_a_value_that_is_not_a_boolean_reads_as_on() {
        let old = r#"{"soundEnabled":true,"soundVolume":0.12,"autoCloseInterval":15,"absenceInterval":180,
            "activeIntegrations":[],"screen":"primary","autostart":false,"hooksInstalled":false}"#;
        let s: Settings = serde_json::from_str(old).unwrap();
        assert!(s.focus_aware);
        assert_eq!(serde_json::to_value(&s).unwrap()["focusAware"], true);
        let with = |v: &str| serde_json::from_str::<Settings>(&old.replace("\"autostart\"", &format!("\"focusAware\":{v},\"autostart\""))).unwrap();
        assert!(!with("false").focus_aware);
        assert!(with("true").focus_aware);
        let odd = with("\"no\"");
        assert!(odd.focus_aware, "a string is not a Boolean");
        assert_eq!(odd.sound_volume, 0.12, "the rest of the file still loads");
        assert!(with("null").focus_aware);
    }

    #[test]
    fn a_settings_file_without_tuck_away_gets_never_and_keeps_only_a_known_choice() {
        let old = r#"{"soundEnabled":true,"soundVolume":0.12,"autoCloseInterval":15,"absenceInterval":180,
            "activeIntegrations":[],"screen":"primary","autostart":false,"hooksInstalled":false}"#;
        let s: Settings = serde_json::from_str(old).unwrap();
        assert_eq!(s.tuck_away, "never");
        assert_eq!(serde_json::to_value(&sanitized(s)).unwrap()["tuckAway"], "never");
        let five: Settings = serde_json::from_str(&old.replace("\"autostart\"", "\"tuckAway\":\"5\",\"autostart\"")).unwrap();
        assert_eq!(sanitized(five).tuck_away, "5");
        let unknown: Settings = serde_json::from_str(&old.replace("\"autostart\"", "\"tuckAway\":\"7\",\"autostart\"")).unwrap();
        assert_eq!(sanitized(unknown).tuck_away, "never");
        assert_eq!(clean_tuck_away("30"), "30");
        assert_eq!(clean_tuck_away(""), "never");
    }

    #[test]
    fn a_settings_file_from_0_1_1_keeps_its_claude_model() {
        let old = r#"{"soundEnabled":true,"soundVolume":0.12,"autoCloseInterval":15,"absenceInterval":180,
            "activeIntegrations":["integration_github"],"screen":"primary","autostart":false,
            "hooksInstalled":true,"model":"claude-opus-5"}"#;
        let s = migrate(serde_json::from_str(old).unwrap());
        assert_eq!(s.ai.cloud_models.get("anthropic").map(String::as_str), Some("claude-opus-5"));
        assert_eq!(s.ai.chat, Choice::default());
        assert!(s.hooks_installed);
        let written = serde_json::to_value(&s).unwrap();
        assert!(written.get("model").is_none(), "the old field is never written back");
        assert_eq!(written["ai"]["chat"], "auto");
        assert_eq!(written["ai"]["files"], "auto");
        assert_eq!(written["ai"]["preferredCloud"], "anthropic");
        assert_eq!(written["ai"]["lastUsedLocal"], serde_json::Value::Null);
    }

    #[test]
    fn a_server_url_loses_its_password_before_it_is_stored_or_shown() {
        let mut s = Settings::default();
        s.ai.custom_server = Some("http://me:hunter2@studio-pc:11434/v1/?key=abc".into());
        let clean = sanitized(s);
        assert_eq!(clean.ai.custom_server.as_deref(), Some("http://studio-pc:11434"));
        let json = serde_json::to_string(&clean).unwrap();
        assert!(!json.contains("hunter2") && !json.contains("abc"), "{json}");

        // Not a URL at all: nothing is kept.
        let mut junk = Settings::default();
        junk.ai.custom_server = Some("not a url".into());
        assert_eq!(sanitized(junk).ai.custom_server, None);
    }

    #[test]
    fn a_settings_file_written_by_hand_is_cleaned_the_way_load_does() {
        let raw = r#"{"soundEnabled":true,"soundVolume":0.12,"autoCloseInterval":15,"absenceInterval":180,
            "activeIntegrations":[],"screen":"primary","autostart":false,"hooksInstalled":false,
            "model":"claude-opus-5","ai":{"customServer":"http://u:p4ss@10.0.0.7:1234/v1"}}"#;
        let s = sanitized(migrate(serde_json::from_str(raw).unwrap()));
        assert_eq!(s.ai.custom_server.as_deref(), Some("http://10.0.0.7:1234"));
        assert_eq!(s.ai.cloud_models.get("anthropic").map(String::as_str), Some("claude-opus-5"));
    }

    /// The pre-E1 default of each provider that stored a model only when it wasn't the default.
    #[test]
    fn a_choice_without_a_stored_model_keeps_its_old_default_instead_of_becoming_auto() {
        let file = |provider: &str| {
            format!(
                r#"{{"soundEnabled":true,"soundVolume":0.12,"autoCloseInterval":15,"absenceInterval":180,
                "activeIntegrations":[],"screen":"primary","autostart":false,"hooksInstalled":false,
                "ai":{{"chat":{{"provider":"{provider}"}},"files":{{"provider":"{provider}"}}}}}}"#
            )
        };
        let explicit = |provider: &str, model: &str| Choice::Explicit(ModelRef { provider: provider.into(), model: model.into() });
        for (provider, model) in [("ollama", "llama3.2"), ("lmstudio", "local-model"), ("google", "gemini-2.0-flash")] {
            let s = migrate(serde_json::from_str(&file(provider)).unwrap());
            assert_eq!(s.ai.chat, explicit(provider, model), "{provider} chat");
            assert_eq!(s.ai.files, explicit(provider, model), "{provider} files");
        }
        // A model that is stored stays; a provider with no old default has nothing to keep.
        let stored = r#"{"soundEnabled":true,"soundVolume":0.12,"autoCloseInterval":15,"absenceInterval":180,
            "activeIntegrations":[],"screen":"primary","autostart":false,"hooksInstalled":false,
            "ai":{"chat":{"provider":"ollama","model":"qwen3.5:2b"},"files":{"provider":"jan"}}}"#;
        let s = migrate(serde_json::from_str(stored).unwrap());
        assert_eq!(s.ai.chat, explicit("ollama", "qwen3.5:2b"));
        assert_eq!(s.ai.files, Choice::default());
    }

    #[test]
    fn a_chosen_model_round_trips() {
        let mut s = Settings::default();
        s.ai.files = Choice::Explicit(ModelRef { provider: "ollama".into(), model: "qwen3.5:2b".into() });
        let back: Settings = serde_json::from_value(serde_json::to_value(&s).unwrap()).unwrap();
        assert_eq!(back.ai, s.ai);
    }

    #[test]
    fn a_settings_file_that_does_not_parse_is_kept_as_a_backup_and_defaults_load() {
        let dir = std::env::temp_dir().join(format!("notchmeow-bad-settings-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("settings.json");
        std::fs::write(&path, r#"{"soundEnabled": tru, "secretNote": "hand-typed"}"#).unwrap();
        let s = checked(&path).0;
        assert!(s.sound_enabled && s.screen == "primary", "defaults load");
        assert!(!path.exists(), "the bad file is moved, not left to be overwritten");
        let backups: Vec<_> = std::fs::read_dir(&dir).unwrap().map(|e| e.unwrap().file_name().into_string().unwrap()).collect();
        assert_eq!(backups.len(), 1, "{backups:?}");
        assert!(backups[0].starts_with("settings.json.bad-"), "{backups:?}");
        assert!(std::fs::read_to_string(dir.join(&backups[0])).unwrap().contains("hand-typed"));
        let logged = crate::log::CAPTURED.lock().unwrap().join("\n");
        assert!(logged.contains(&backups[0]) && !logged.contains("hand-typed"), "{logged}");

        // A file that parses is not touched and still migrates.
        std::fs::write(&path, r#"{"soundEnabled":true,"soundVolume":0.12,"autoCloseInterval":15,"absenceInterval":180,
            "activeIntegrations":[],"screen":"cursor","autostart":false,"hooksInstalled":false,"model":"claude-opus-5"}"#).unwrap();
        let ok = checked(&path).0;
        assert!(path.exists() && ok.screen == "cursor");
        assert_eq!(ok.ai.cloud_models.get("anthropic").map(String::as_str), Some("claude-opus-5"));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn when_the_rename_fails_the_file_is_copied_and_the_failure_is_logged_without_content() {
        let dir = std::env::temp_dir().join(format!("notchmeow-bad-rename-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("settings.json");
        std::fs::write(&path, r#"{"soundEnabled": tru, "secretNote": "locked-note"}"#).unwrap();
        let denied = |_: &std::path::Path, _: &std::path::Path| Err(std::io::Error::from(std::io::ErrorKind::PermissionDenied));
        let (s, _) = load_checked_with(&path, denied, |from: &Path, to: &Path| std::fs::copy(from, to));
        assert!(s.sound_enabled, "defaults load");
        assert!(path.exists(), "the original stays where it is");
        let backup = std::fs::read_dir(&dir).unwrap().map(|e| e.unwrap().file_name().into_string().unwrap()).find(|n| n.starts_with("settings.json.bad-")).expect("a copy");
        assert!(std::fs::read_to_string(dir.join(&backup)).unwrap().contains("locked-note"));
        let logged = crate::log::CAPTURED.lock().unwrap().iter().filter(|l| l.contains(&backup)).cloned().collect::<Vec<_>>().join("\n");
        assert!(logged.contains("copied") && !logged.contains("locked-note"), "{logged}");

        // Neither works (the file can't even be copied): still logged, still no content.
        std::fs::write(&path, "{ not json locked-note").unwrap();
        // The rename seam deletes the source first, so the copy that follows has nothing to copy.
        let (_, problem) = load_checked_with(&path, |from, _| {
            let _ = std::fs::remove_file(from);
            Err(std::io::Error::from(std::io::ErrorKind::PermissionDenied))
        }, |from: &Path, to: &Path| std::fs::copy(from, to));
        // Nothing could be kept, and the file may still be there: saves stay refused.
        assert_eq!(problem, Some(LoadProblem::Unreadable));
        // (CAPTURED is shared with parallel tests: look only at this failure's line.)
        let logged = crate::log::CAPTURED.lock().unwrap().iter().filter(|l| l.contains("could not keep a backup")).cloned().collect::<Vec<_>>().join("\n");
        assert!(!logged.is_empty() && !logged.contains("locked-note"), "{logged}");
        let _ = std::fs::remove_dir_all(&dir);
    }

    const OLD_FILE: &str = r#"{"soundEnabled":false,"soundVolume":0.12,"autoCloseInterval":15,"absenceInterval":180,
        "activeIntegrations":[],"screen":"cursor","autostart":false,"hooksInstalled":false"#;

    #[test]
    fn a_settings_file_from_before_the_cat_section_gets_the_default_cat() {
        let s = sanitized(migrate(serde_json::from_str(&format!("{OLD_FILE}}}")).unwrap()));
        assert_eq!(s.cat, crate::cat_settings::block_default());
        assert_eq!(s.cat["character"], "shrimpy");
        assert_eq!((&s.cat["displayMode"], &s.cat["pair"], &s.cat["agentCats"]), (&serde_json::json!("one"), &serde_json::json!(["shrimpy", "momo"]), &serde_json::json!({})));
        assert_eq!(s.cat["cats"].as_object().unwrap().len(), 16);
        assert_eq!(serde_json::to_value(&s).unwrap()["cat"], s.cat, "the block is written back as it is held");
    }

    /// A typed `cat` field would reject every one of these, and `load` would then move the whole file aside.
    #[test]
    fn one_bad_field_in_the_cat_block_never_fails_the_settings_file() {
        let dir = std::env::temp_dir().join(format!("notchmeow-bad-cat-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("settings.json");
        for cat in [
            "5",
            r#""junk""#,
            "[1,2]",
            "null",
            r#"{"character":7,"motionStyle":[],"collar":{"a":1},"furLines":"yes","cats":"x"}"#,
            r#"{"cats":{"momo":{"personality":"{not json","motion":9},"ginger":[1],"tiger":{}}}"#,
        ] {
            std::fs::write(&path, format!(r#"{OLD_FILE},"cat":{cat}}}"#)).unwrap();
            let s = checked(&path).0;
            assert!(!s.sound_enabled && s.screen == "cursor", "the rest of the file is kept: {cat}");
            assert_eq!(s.cat, crate::cat_settings::block_default(), "{cat}");
            assert!(path.exists(), "the file is not moved aside: {cat}");
        }
        let backups = std::fs::read_dir(&dir).unwrap().filter(|e| e.as_ref().unwrap().file_name().to_string_lossy().starts_with("settings.json.bad-")).count();
        assert_eq!(backups, 0);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_good_cat_block_survives_a_round_trip_and_what_the_webview_sends_is_cleaned() {
        let mut s = Settings::default();
        s.cat = serde_json::json!({
            "character": "momo", "motionStyle": "classic", "collar": "band", "furLines": true,
            "cats": {"momo": {"motion": "playful", "collar": "off", "personality": {"preset": "custom", "energy": 0.27, "curiosity": 0.83, "chatty": 0.41, "affection": 0.58, "sass": 0.12, "mischief": 0.99}}}
        });
        let kept = sanitized(s.clone());
        let back: Settings = serde_json::from_value(serde_json::to_value(&kept).unwrap()).unwrap();
        assert_eq!(back.cat, kept.cat);
        assert_eq!(kept.cat["character"], "momo");
        assert_eq!(kept.cat["cats"]["momo"]["motion"], "playful");
        assert_eq!(kept.cat["cats"]["momo"]["collar"], "off");
        assert_eq!(kept.cat["cats"]["momo"]["personality"]["energy"].as_f64(), Some(0.27));
        assert_eq!(kept.cat["cats"]["ginger"]["motion"], "follow");
        // The webview is not trusted: a hostile block is cleaned before it is stored, saved or shared (`save_settings` runs `sanitized`).
        s.cat = serde_json::json!({"character": "tiger", "motionStyle": 3, "furLines": "true", "cats": {"momo": {"motion": "bogus"}}, "extra": 1});
        let cleaned = sanitized(s);
        assert_eq!(cleaned.cat["character"], "shrimpy");
        assert_eq!(cleaned.cat["furLines"], false);
        assert_eq!(cleaned.cat["cats"]["momo"]["motion"], "follow");
        assert!(cleaned.cat.get("extra").is_none());
    }

    /// The three display keys sit in the same `cat` block as the Cat settings, which `sanitized` used to rebuild from the Cat settings alone: a save dropped them.
    #[test]
    fn the_display_settings_survive_a_save_a_load_and_a_round_trip() {
        let dir = std::env::temp_dir().join(format!("notchmeow-display-keys-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("settings.json");
        let mut s = Settings::default();
        s.cat = serde_json::json!({
            "character": "momo", "collar": "band",
            "displayMode": "perAgent", "pair": ["latte", "cloud"], "agentCats": {"agent_gemini": "oreo", "integration_claude": "leo"}
        });
        // `save_settings` cleans what the webview sends, stores it and writes it: the same three steps, with the file under a temporary folder.
        let sent = sanitized(s);
        assert_eq!(sent.cat["displayMode"], "perAgent");
        std::fs::write(&path, serde_json::to_vec_pretty(&sent).unwrap()).unwrap();
        let back = checked(&path).0;
        assert_eq!(back.cat, sent.cat, "what was saved is what loads");
        assert_eq!(back.cat["displayMode"], "perAgent");
        assert_eq!(back.cat["pair"], serde_json::json!(["latte", "cloud"]));
        assert_eq!(back.cat["agentCats"], serde_json::json!({"agent_gemini": "oreo", "integration_claude": "leo"}));
        assert_eq!(back.cat["character"], "momo", "the Cat settings are still there");
        let again: Settings = serde_json::from_value(serde_json::to_value(&back).unwrap()).unwrap();
        assert_eq!(sanitized(again).cat, back.cat, "a second round trip changes nothing");
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// The desktop cat's settings sit in the same `cat` block: a save keeps them, a load gives them back, and `sanitized` cleans them.
    #[test]
    fn the_desktop_settings_survive_a_save_a_load_and_a_round_trip() {
        let dir = std::env::temp_dir().join(format!("notchmeow-desktop-keys-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("settings.json");
        let mut s = Settings::default();
        s.cat = serde_json::json!({
            "character": "momo", "displayMode": "two",
            "desktop": {"on": true, "size": "large", "spots": {"0,0,1512,982": {"x": 300, "y": 400}, "0,0,1512,982|1512,-100,2560,1440": {"x": 2000, "y": 800}}}
        });
        let sent = sanitized(s);
        assert_eq!(sent.cat["desktop"]["on"], true);
        std::fs::write(&path, serde_json::to_vec_pretty(&sent).unwrap()).unwrap();
        let back = checked(&path).0;
        assert_eq!(back.cat, sent.cat, "what was saved is what loads");
        assert_eq!(back.cat["desktop"]["size"], "large");
        assert_eq!(back.cat["desktop"]["spots"]["0,0,1512,982"]["x"], 300);
        assert_eq!(back.cat["desktop"]["spots"]["0,0,1512,982|1512,-100,2560,1440"]["y"], 800);
        assert_eq!((&back.cat["character"], &back.cat["displayMode"]), (&serde_json::json!("momo"), &serde_json::json!("two")), "the other two parts are still there");
        let again: Settings = serde_json::from_value(serde_json::to_value(&back).unwrap()).unwrap();
        assert_eq!(sanitized(again).cat, back.cat, "a second round trip changes nothing");
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// The project cats sit in the same `cat` block: a save keeps the valid entry, a load gives it back, and a path-like key, an invisible key, an unknown cat and a
    /// list in place of the map are dropped without failing the file (`clean_project_cats`, the Mac's cleanProjectCats).
    #[test]
    fn the_project_cats_survive_a_save_a_load_and_a_round_trip_and_bad_ones_are_dropped() {
        let dir = std::env::temp_dir().join(format!("notchmeow-project-cats-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("settings.json");
        let mut s = Settings::default();
        s.cat = serde_json::json!({
            "character": "momo", "displayMode": "two",
            "projectCats": {"notchmeow": "oreo", "C:/dev/secret": "momo", "bad\u{200B}key": "momo", "unknown": "tiger"}
        });
        let sent = sanitized(s);
        assert_eq!(sent.cat["projectCats"], serde_json::json!({"notchmeow": "oreo"}), "a save keeps the one valid entry");
        std::fs::write(&path, serde_json::to_vec_pretty(&sent).unwrap()).unwrap();
        let back = checked(&path).0;
        assert_eq!(back.cat, sent.cat, "what was saved is what loads");
        assert_eq!(back.cat["projectCats"], serde_json::json!({"notchmeow": "oreo"}));
        assert_eq!((&back.cat["character"], &back.cat["displayMode"]), (&serde_json::json!("momo"), &serde_json::json!("two")), "the other parts are still there");
        let again: Settings = serde_json::from_value(serde_json::to_value(&back).unwrap()).unwrap();
        assert_eq!(sanitized(again).cat, back.cat, "a second round trip changes nothing");
        // A hand-edited file: each bad entry goes, the good one stays, and a list in place of the map is an empty map.
        for (cat, expect) in [
            (r#"{"character":"momo","projectCats":{"notchmeow":"oreo","a/b":"momo","x":"tiger","b\u200bc":"momo","k":7}}"#, serde_json::json!({"notchmeow": "oreo"})),
            (r#"{"character":"momo","projectCats":["notchmeow"]}"#, serde_json::json!({})),
        ] {
            std::fs::write(&path, format!(r#"{OLD_FILE},"cat":{cat}}}"#)).unwrap();
            let s = checked(&path).0;
            assert!(!s.sound_enabled && s.screen == "cursor", "the rest of the file is kept: {cat}");
            assert_eq!((&s.cat["projectCats"], &s.cat["character"]), (&expect, &serde_json::json!("momo")), "{cat}");
        }
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// The wardrobe's `outfit` sits in the same `cat` block: a save keeps it, a load gives it back, and a bad one is auto without failing the file.
    #[test]
    fn the_outfit_survives_a_save_a_load_and_a_round_trip_and_a_bad_one_is_auto() {
        let dir = std::env::temp_dir().join(format!("notchmeow-outfit-key-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("settings.json");
        let mut s = Settings::default();
        s.cat = serde_json::json!({"character": "momo", "displayMode": "two", "desktop": {"on": true, "size": "large"}, "outfit": "blossomclip"});
        let sent = sanitized(s);
        assert_eq!(sent.cat["outfit"], "blossomclip");
        std::fs::write(&path, serde_json::to_vec_pretty(&sent).unwrap()).unwrap();
        let back = checked(&path).0;
        assert_eq!(back.cat, sent.cat, "what was saved is what loads");
        assert_eq!((&back.cat["outfit"], &back.cat["displayMode"], &back.cat["desktop"]["size"]), (&serde_json::json!("blossomclip"), &serde_json::json!("two"), &serde_json::json!("large")), "the other parts are still there");
        let again: Settings = serde_json::from_value(serde_json::to_value(&back).unwrap()).unwrap();
        assert_eq!(sanitized(again).cat, back.cat, "a second round trip changes nothing");
        for cat in [r#"{"character":"momo","outfit":7}"#, r#"{"character":"momo","outfit":"Santahat"}"#, r#"{"character":"momo","outfit":["bow"]}"#, r#"{"character":"momo"}"#] {
            std::fs::write(&path, format!(r#"{OLD_FILE},"cat":{cat}}}"#)).unwrap();
            let s = checked(&path).0;
            assert!(!s.sound_enabled && s.screen == "cursor", "the rest of the file is kept: {cat}");
            assert_eq!((&s.cat["outfit"], &s.cat["character"]), (&serde_json::json!("auto"), &serde_json::json!("momo")), "{cat}");
            assert!(path.exists(), "the file is not moved aside: {cat}");
        }
        let backups = std::fs::read_dir(&dir).unwrap().filter(|e| e.as_ref().unwrap().file_name().to_string_lossy().starts_with("settings.json.bad-")).count();
        assert_eq!(backups, 0);
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// A hand-edited file with a bad `desktop` is cleaned without failing the file or touching the rest of the block.
    #[test]
    fn bad_desktop_values_are_cleaned_and_never_fail_the_settings_file() {
        let dir = std::env::temp_dir().join(format!("notchmeow-bad-desktop-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("settings.json");
        for cat in [
            r#"{"character":"momo","desktop":7}"#,
            r#"{"character":"momo","desktop":null}"#,
            r#"{"character":"momo","desktop":{"on":"true","size":["small"],"spots":"{not json"}}"#,
            r#"{"character":"momo","desktop":{"on":1,"size":"HUGE","spots":{"__proto__":{"x":1,"y":1},"0,0,1,1":{"x":"a","y":1}}}}"#,
        ] {
            std::fs::write(&path, format!(r#"{OLD_FILE},"cat":{cat}}}"#)).unwrap();
            let s = checked(&path).0;
            assert!(!s.sound_enabled && s.screen == "cursor", "the rest of the file is kept: {cat}");
            assert_eq!(s.cat["character"], "momo", "the Cat settings next to it are kept: {cat}");
            assert_eq!(s.cat["desktop"], serde_json::json!({"on": false, "size": "medium", "spots": {}}), "{cat}");
            assert!(path.exists(), "the file is not moved aside: {cat}");
        }
        let backups = std::fs::read_dir(&dir).unwrap().filter(|e| e.as_ref().unwrap().file_name().to_string_lossy().starts_with("settings.json.bad-")).count();
        assert_eq!(backups, 0);
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// The webview is not trusted, and a hand-edited file is not either: bad display keys are cleaned without failing the file or touching the rest of the block.
    #[test]
    fn bad_display_keys_are_cleaned_and_one_of_them_never_fails_the_settings_file() {
        let dir = std::env::temp_dir().join(format!("notchmeow-bad-display-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("settings.json");
        for cat in [
            r#"{"character":"momo","displayMode":7,"pair":"[\"momo\"","agentCats":[1,2]}"#,
            r#"{"character":"momo","displayMode":"both","pair":["momo","tiger"],"agentCats":{"__proto__":"momo","Agent_X":"momo","agent_ok":"tiger","integration_claude":7}}"#,
            r#"{"character":"momo","displayMode":null,"pair":null,"agentCats":null}"#,
        ] {
            std::fs::write(&path, format!(r#"{OLD_FILE},"cat":{cat}}}"#)).unwrap();
            let s = checked(&path).0;
            assert!(!s.sound_enabled && s.screen == "cursor", "the rest of the file is kept: {cat}");
            assert_eq!(s.cat["character"], "momo", "the Cat settings next to them are kept: {cat}");
            assert_eq!(s.cat["displayMode"], "one", "{cat}");
            assert_eq!(s.cat["pair"], serde_json::json!(["shrimpy", "momo"]), "{cat}");
            assert!(s.cat["agentCats"].as_object().unwrap().keys().all(|k| crate::cat_settings::is_pill_id(k)), "{cat}");
            assert!(path.exists(), "the file is not moved aside: {cat}");
        }
        // The webview's own save is cleaned the same way.
        let mut s = Settings::default();
        s.cat = serde_json::json!({"displayMode": "two", "pair": ["momo", "momo"], "agentCats": {"agent_x": "snow", "constructor": "momo"}});
        let cleaned = sanitized(s);
        assert_eq!(cleaned.cat["pair"], serde_json::json!(["momo", "ginger"]));
        assert_eq!(cleaned.cat["agentCats"], serde_json::json!({"agent_x": "snow"}));
        let backups = std::fs::read_dir(&dir).unwrap().filter(|e| e.as_ref().unwrap().file_name().to_string_lossy().starts_with("settings.json.bad-")).count();
        assert_eq!(backups, 0);
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// The Sidekick settings are an object of their own beside the `cat` block: a save keeps them, a load gives them back, and a settings file from before F1 gets the defaults.
    #[test]
    fn the_sidekick_settings_survive_a_save_a_load_and_a_round_trip() {
        let dir = std::env::temp_dir().join(format!("notchmeow-sidekick-keys-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("settings.json");
        let mut s = Settings::default();
        s.sidekick = serde_json::json!({"on": false, "local": true, "dismissals": {"recap": 2, "stuck.loop": 1}});
        // `save_settings` cleans what the webview sends, stores it and writes it: the same three steps, with the file under a temporary folder.
        let sent = sanitized(s);
        assert_eq!(sent.sidekick["on"], false);
        std::fs::write(&path, serde_json::to_vec_pretty(&sent).unwrap()).unwrap();
        let back = checked(&path).0;
        assert_eq!(back.sidekick, sent.sidekick, "what was saved is what loads");
        assert_eq!(back.sidekick["dismissals"], serde_json::json!({"recap": 2, "stuck.loop": 1, "stuck.errors": 0, "stuck.waiting": 0, "stuck.silent": 0}));
        let again: Settings = serde_json::from_value(serde_json::to_value(&back).unwrap()).unwrap();
        assert_eq!(sanitized(again).sidekick, back.sidekick, "a second round trip changes nothing");
        // A save that changes only other settings still carries the object: it is part of `Settings`, so a clean-up of anything else never drops it.
        let mut other = back.clone();
        other.sound_enabled = !other.sound_enabled;
        assert_eq!(sanitized(other).sidekick, sent.sidekick);
        // A file from before F1 has no such object: everything is on and nothing is dismissed.
        std::fs::write(&path, format!("{OLD_FILE}}}")).unwrap();
        assert_eq!(checked(&path).0.sidekick, crate::sidekick_settings::default_value());
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// A typed `sidekick` field would reject every one of these, and `load` would then move the whole file aside.
    #[test]
    fn one_bad_field_in_the_sidekick_object_never_fails_the_settings_file() {
        let dir = std::env::temp_dir().join(format!("notchmeow-bad-sidekick-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("settings.json");
        for sidekick in ["5", r#""junk""#, "[1,2]", "null", r#"{"on":"no","local":[],"dismissals":"all"}"#, r#"{"dismissals":{"recap":"x","stuck.loop":-1,"nope":2},"extra":1}"#] {
            std::fs::write(&path, format!(r#"{OLD_FILE},"sidekick":{sidekick}}}"#)).unwrap();
            let s = checked(&path).0;
            assert!(!s.sound_enabled && s.screen == "cursor", "the rest of the file is kept: {sidekick}");
            assert_eq!(s.sidekick, crate::sidekick_settings::default_value(), "{sidekick}");
            assert!(path.exists(), "the file is not moved aside: {sidekick}");
        }
        let backups = std::fs::read_dir(&dir).unwrap().filter(|e| e.as_ref().unwrap().file_name().to_string_lossy().starts_with("settings.json.bad-")).count();
        assert_eq!(backups, 0);
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// The companion settings are an object of their own beside the `sidekick` block: a save keeps them, a load gives them back, and a file from before F3a gets the defaults.
    #[test]
    fn the_companion_settings_survive_a_save_a_load_and_a_round_trip() {
        let dir = std::env::temp_dir().join(format!("notchmeow-companion-keys-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("settings.json");
        let mut s = Settings::default();
        s.companion = serde_json::json!({"humor": "more", "seeSessions": false, "cloudNoticeShown": ["openai", "anthropic"]});
        let sent = sanitized(s);
        assert_eq!(sent.companion["humor"], "more");
        assert_eq!(sent.companion["cloudNoticeShown"], serde_json::json!(["anthropic", "openai"]));
        std::fs::write(&path, serde_json::to_vec_pretty(&sent).unwrap()).unwrap();
        let back = checked(&path).0;
        assert_eq!(back.companion, sent.companion, "what was saved is what loads");
        let again: Settings = serde_json::from_value(serde_json::to_value(&back).unwrap()).unwrap();
        assert_eq!(sanitized(again).companion, back.companion, "a second round trip changes nothing");
        // A save that changes only other settings still carries the object.
        let mut other = back.clone();
        other.sound_enabled = !other.sound_enabled;
        assert_eq!(sanitized(other).companion, sent.companion);
        // A file from before F3a has no such object: the defaults.
        std::fs::write(&path, format!("{OLD_FILE}}}")).unwrap();
        assert_eq!(checked(&path).0.companion, crate::companion_settings::default_value());
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// A typed `companion` field would reject every one of these, and `load` would then move the whole file aside.
    #[test]
    fn one_bad_field_in_the_companion_object_never_fails_the_settings_file() {
        let dir = std::env::temp_dir().join(format!("notchmeow-bad-companion-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("settings.json");
        for companion in ["5", r#""junk""#, "[1,2]", "null", r#"{"humor":{},"cloudNoticeShown":"anthropic"}"#, r#"{"recapDismissals":"x","lastRecapDay":"2026-02-30","extra":1}"#] {
            std::fs::write(&path, format!(r#"{OLD_FILE},"companion":{companion}}}"#)).unwrap();
            let s = checked(&path).0;
            assert!(!s.sound_enabled && s.screen == "cursor", "the rest of the file is kept: {companion}");
            assert_eq!(s.companion, crate::companion_settings::default_value(), "{companion}");
            assert!(path.exists(), "the file is not moved aside: {companion}");
        }
        let backups = std::fs::read_dir(&dir).unwrap().filter(|e| e.as_ref().unwrap().file_name().to_string_lossy().starts_with("settings.json.bad-")).count();
        assert_eq!(backups, 0);
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// The write comes first: a failed write leaves the shared copy exactly as it was.
    #[test]
    fn a_failed_write_leaves_the_shared_settings_as_they_were() {
        let current = Mutex::new(Settings::default());
        let mut next = Settings::default();
        next.screen = "cursor".into();
        let failed = commit(&current, next, |_| Err(std::io::Error::from(std::io::ErrorKind::PermissionDenied)));
        assert!(failed.is_err());
        assert_eq!(current.lock().unwrap().screen, "primary", "the shared copy is unchanged");
    }

    /// A write that works is what the file now holds, and the shared copy is swapped for it; the value it replaced comes back so the side effects can see what changed.
    #[test]
    fn a_written_value_replaces_the_shared_copy_and_returns_the_previous_one() {
        let current = Mutex::new(Settings::default());
        let mut next = Settings::default();
        next.screen = "cursor".into();
        let seen = std::cell::RefCell::new(String::new());
        let previous = commit(&current, next, |s| {
            *seen.borrow_mut() = s.screen.clone();
            Ok(())
        })
        .expect("a write that works");
        assert_eq!(previous.screen, "primary");
        assert_eq!(*seen.borrow(), "cursor", "the file is written with the new value");
        assert_eq!(current.lock().unwrap().screen, "cursor");
    }

    /// A change that is not written changes nothing: the shared copy keeps its value, and the caller hears why.
    #[test]
    fn a_change_that_cannot_be_written_leaves_the_shared_copy_and_is_reported() {
        let current = Mutex::new(Settings::default());
        let refused = update(&current, |s| { s.hooks_installed = true; true }, |_| Err(std::io::Error::from(std::io::ErrorKind::PermissionDenied)));
        assert!(refused.is_err());
        assert!(!current.lock().unwrap().hooks_installed, "the hook flag on disk is not written, so the shared copy must not claim it");
    }

    /// A change that is written is held and returned; a change that makes no difference writes nothing and returns nothing.
    #[test]
    fn a_written_change_is_held_and_one_that_changes_nothing_is_not_written() {
        let current = Mutex::new(Settings::default());
        let writes = std::cell::Cell::new(0);
        let held = update(&current, |s| { s.hooks_installed = true; true }, |_| { writes.set(writes.get() + 1); Ok(()) })
            .expect("a write that works")
            .expect("a change");
        assert!(held.hooks_installed && current.lock().unwrap().hooks_installed);
        assert_eq!(writes.get(), 1);
        let same = update(&current, |_| false, |_| { writes.set(writes.get() + 1); Ok(()) }).expect("nothing to do");
        assert!(same.is_none());
        assert_eq!(writes.get(), 1, "no write for no change");
    }

    /// A save goes through a temp file beside settings.json and is renamed over it: a rename that fails leaves the old file whole and no temp behind.
    #[test]
    fn a_failed_rename_leaves_the_old_settings_file_intact_and_removes_the_temp() {
        let dir = scratch("save-rename-fails");
        let path = dir.join("settings.json");
        std::fs::write(&path, VALID).unwrap();
        let blocked = AtomicBool::new(false);
        let failed = save_with(&blocked, &path, &Settings::default(), |_, _| Err(std::io::Error::from(std::io::ErrorKind::PermissionDenied)));
        assert!(failed.is_err());
        assert_eq!(std::fs::read_to_string(&path).unwrap(), VALID, "the old file is untouched");
        assert_eq!(names(&dir), vec!["settings.json".to_string()], "the temp is removed");
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// A save that works writes the new file through the rename, and leaves no temp.
    #[test]
    fn a_save_replaces_the_file_through_a_temp_and_leaves_nothing_behind() {
        let dir = scratch("save-renames");
        let path = dir.join("settings.json");
        std::fs::write(&path, VALID).unwrap();
        let blocked = AtomicBool::new(false);
        let mut next = Settings::default();
        next.screen = "cursor".into();
        save_with(&blocked, &path, &next, rename_over).expect("written");
        let back: Settings = serde_json::from_str(&std::fs::read_to_string(&path).unwrap()).unwrap();
        assert_eq!(back.screen, "cursor");
        assert_eq!(names(&dir), vec!["settings.json".to_string()], "the temp was renamed over the file");
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// A save through a symlink (a dotfiles setup) keeps the link and writes the file it points at.
    #[cfg(unix)]
    #[test]
    fn a_save_through_a_symlink_keeps_the_link_and_writes_its_target() {
        use std::os::unix::fs::symlink;
        let dir = scratch("save-symlink");
        let target = dir.join("dotfiles-settings.json");
        let path = dir.join("settings.json");
        std::fs::write(&target, VALID).unwrap();
        symlink(&target, &path).unwrap();
        let mut next = Settings::default();
        next.screen = "cursor".into();
        save_with(&AtomicBool::new(false), &path, &next, rename_over).expect("written");
        assert!(std::fs::symlink_metadata(&path).unwrap().file_type().is_symlink(), "the link survives the save");
        let back: Settings = serde_json::from_str(&std::fs::read_to_string(&target).unwrap()).unwrap();
        assert_eq!(back.screen, "cursor", "the target holds the new content");
        assert_eq!(names(&dir), vec!["dotfiles-settings.json".to_string(), "settings.json".to_string()], "no temp is left");
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// A save keeps the mode of the file it replaces. 0o640 is not any common umask's result, so the test holds under any umask.
    #[cfg(unix)]
    #[test]
    fn a_save_keeps_the_mode_of_the_file_it_replaces() {
        use std::os::unix::fs::PermissionsExt;
        let dir = scratch("save-mode");
        let path = dir.join("settings.json");
        std::fs::write(&path, VALID).unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o640)).unwrap();
        save_with(&AtomicBool::new(false), &path, &Settings::default(), rename_over).expect("written");
        assert_eq!(std::fs::metadata(&path).unwrap().permissions().mode() & 0o777, 0o640);
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// A link whose target does not exist yet is written through: the target is created and the link survives.
    #[cfg(unix)]
    #[test]
    fn a_save_through_a_dangling_symlink_creates_its_target_and_keeps_the_link() {
        use std::os::unix::fs::symlink;
        let dir = scratch("save-dangling");
        let target = dir.join("later.json");
        let path = dir.join("settings.json");
        symlink(&target, &path).unwrap();
        let mut next = Settings::default();
        next.screen = "cursor".into();
        save_with(&AtomicBool::new(false), &path, &next, rename_over).expect("written");
        assert!(std::fs::symlink_metadata(&path).unwrap().file_type().is_symlink(), "the link survives");
        let back: Settings = serde_json::from_str(&std::fs::read_to_string(&target).unwrap()).unwrap();
        assert_eq!(back.screen, "cursor", "the target was created with the new content");
        assert_eq!(names(&dir), vec!["later.json".to_string(), "settings.json".to_string()], "no temp is left");
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// Links that point at each other are refused, and nothing is touched.
    #[cfg(unix)]
    #[test]
    fn a_save_through_a_loop_of_links_is_refused_and_touches_nothing() {
        use std::os::unix::fs::symlink;
        let dir = scratch("save-loop");
        let a = dir.join("settings.json");
        let b = dir.join("other.json");
        symlink(&b, &a).unwrap();
        symlink(&a, &b).unwrap();
        assert!(save_with(&AtomicBool::new(false), &a, &Settings::default(), rename_over).is_err());
        assert!(std::fs::symlink_metadata(&a).unwrap().file_type().is_symlink());
        assert!(std::fs::symlink_metadata(&b).unwrap().file_type().is_symlink());
        assert_eq!(names(&dir), vec!["other.json".to_string(), "settings.json".to_string()], "no temp is left");
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// A links loop is refused before the folder is touched: `ensure_private_dir` (0700 on Linux) must not run for a save that was never going to happen.
    #[cfg(unix)]
    #[test]
    fn a_refused_link_loop_leaves_the_folders_mode_alone() {
        use std::os::unix::fs::{symlink, PermissionsExt};
        let dir = scratch("save-loop-mode");
        std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(0o755)).unwrap();
        let a = dir.join("settings.json");
        let b = dir.join("other.json");
        symlink(&b, &a).unwrap();
        symlink(&a, &b).unwrap();
        assert!(save_with(&AtomicBool::new(false), &a, &Settings::default(), rename_over).is_err());
        assert_eq!(std::fs::metadata(&dir).unwrap().permissions().mode() & 0o777, 0o755, "the folder was not chmodded");
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// A settings.json the user made read-only (mode without the owner's write bit) is not replaced: the old `fs::write` refused it, and a rename would not.
    /// Nothing is written, nothing is left behind, and the error is the one the page already words ("Couldn't save the settings.").
    #[cfg(unix)]
    #[test]
    fn a_read_only_settings_file_is_refused_and_left_whole() {
        use std::os::unix::fs::PermissionsExt;
        let dir = scratch("save-read-only");
        let path = dir.join("settings.json");
        std::fs::write(&path, VALID).unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o444)).unwrap();
        let err = save_with(&AtomicBool::new(false), &path, &Settings::default(), rename_over).expect_err("a read-only file is not replaced");
        assert_eq!(err.kind(), std::io::ErrorKind::PermissionDenied);
        assert_eq!(std::fs::read_to_string(&path).unwrap(), VALID, "the file is untouched");
        assert_eq!(std::fs::metadata(&path).unwrap().permissions().mode() & 0o777, 0o444);
        assert_eq!(names(&dir), vec!["settings.json".to_string()], "no temp is left");
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// Stow-style dotfiles make the link relative: it is followed from the link's own folder, up (`../x.json`) or down (`sub/real.json`).
    #[cfg(unix)]
    #[test]
    fn a_save_through_a_relative_symlink_writes_the_target_it_names() {
        use std::os::unix::fs::symlink;
        let dir = scratch("save-relative");
        std::fs::create_dir_all(dir.join("sub")).unwrap();
        std::fs::create_dir_all(dir.join("home")).unwrap();
        std::fs::write(dir.join("sub").join("real.json"), VALID).unwrap();
        std::fs::write(dir.join("x.json"), VALID).unwrap();
        let mut next = Settings::default();
        next.screen = "cursor".into();
        symlink("sub/real.json", dir.join("settings.json")).unwrap();
        save_with(&AtomicBool::new(false), &dir.join("settings.json"), &next, rename_over).expect("written");
        assert!(std::fs::symlink_metadata(dir.join("settings.json")).unwrap().file_type().is_symlink());
        let down: Settings = serde_json::from_str(&std::fs::read_to_string(dir.join("sub").join("real.json")).unwrap()).unwrap();
        assert_eq!(down.screen, "cursor", "a link into a folder below");
        symlink("../x.json", dir.join("home").join("settings.json")).unwrap();
        save_with(&AtomicBool::new(false), &dir.join("home").join("settings.json"), &next, rename_over).expect("written");
        let up: Settings = serde_json::from_str(&std::fs::read_to_string(dir.join("x.json")).unwrap()).unwrap();
        assert_eq!(up.screen, "cursor", "a link into the folder above");
        assert_eq!(names(&dir.join("sub")), vec!["real.json".to_string()], "no temp is left");
        assert_eq!(names(&dir.join("home")), vec!["settings.json".to_string()], "no temp is left");
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// A temp of the same name left by a crashed run is replaced, not an obstacle.
    #[cfg(unix)]
    #[test]
    fn a_stale_temp_of_the_same_name_is_replaced() {
        let dir = scratch("save-stale-temp");
        let path = dir.join("settings.json");
        std::fs::write(&path, VALID).unwrap();
        let stale = dir.join(format!("settings.json.notchmeow-{}", std::process::id()));
        std::fs::write(&stale, "junk from a crashed run").unwrap();
        let mut next = Settings::default();
        next.screen = "cursor".into();
        save_with(&AtomicBool::new(false), &path, &next, rename_over).expect("written");
        let back: Settings = serde_json::from_str(&std::fs::read_to_string(&path).unwrap()).unwrap();
        assert_eq!(back.screen, "cursor");
        assert_eq!(names(&dir), vec!["settings.json".to_string()], "the stale temp is gone");
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// A link planted at the temp's name is removed, never followed: the file it points at is not written.
    #[cfg(unix)]
    #[test]
    fn a_symlink_planted_at_the_temp_name_is_not_followed() {
        use std::os::unix::fs::symlink;
        let dir = scratch("save-planted-temp");
        let path = dir.join("settings.json");
        let victim = dir.join("victim.txt");
        std::fs::write(&path, VALID).unwrap();
        std::fs::write(&victim, "not yours").unwrap();
        symlink(&victim, dir.join(format!("settings.json.notchmeow-{}", std::process::id()))).unwrap();
        let mut next = Settings::default();
        next.screen = "cursor".into();
        save_with(&AtomicBool::new(false), &path, &next, rename_over).expect("written");
        assert_eq!(std::fs::read_to_string(&victim).unwrap(), "not yours", "the planted link's target is untouched");
        let back: Settings = serde_json::from_str(&std::fs::read_to_string(&path).unwrap()).unwrap();
        assert_eq!(back.screen, "cursor");
        assert_eq!(names(&dir), vec!["settings.json".to_string(), "victim.txt".to_string()], "the link is gone, the victim stays");
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// The process-wide gate closes only for an unreadable file: an unparseable one has a backup, and no problem is no problem. This is the one test that touches
    /// the global `SAVE_BLOCKED` (no other test calls `save`), and it leaves it open.
    #[test]
    fn the_save_gate_closes_only_for_an_unreadable_file() {
        set_save_gate(&Some(LoadProblem::Unreadable));
        assert!(SAVE_BLOCKED.load(Ordering::SeqCst), "closed for an unreadable file");
        set_save_gate(&Some(LoadProblem::Unparseable { kept_as: "settings.json.bad-1".into() }));
        assert!(!SAVE_BLOCKED.load(Ordering::SeqCst), "open for an unparseable one");
        set_save_gate(&Some(LoadProblem::Unreadable));
        set_save_gate(&None);
        assert!(!SAVE_BLOCKED.load(Ordering::SeqCst), "open again with no problem");
    }

    /// "Launch at startup" is changed first and the file written after: a startup change the system refuses writes nothing and says so; a file that then refuses puts the
    /// startup change back. Neither sentence carries a path or the system's own text.
    #[test]
    fn a_save_changes_launch_at_startup_first_and_puts_it_back_when_the_file_refuses() {
        use std::cell::RefCell;
        let calls = RefCell::new(Vec::<String>::new());
        let set = |ok: bool| {
            let calls = &calls;
            move |on: bool| {
                calls.borrow_mut().push(format!("startup {on}"));
                ok
            }
        };
        let write = |ok: bool| {
            let calls = &calls;
            move || -> std::io::Result<&'static str> {
                calls.borrow_mut().push("write".to_string());
                if ok { Ok("saved") } else { Err(std::io::Error::from(std::io::ErrorKind::PermissionDenied)) }
            }
        };

        // No change to startup: the system is not asked at all.
        assert_eq!(save_in_step(true, true, set(true), write(true)), Ok("saved"));
        assert_eq!(calls.borrow().as_slice(), ["write"]);
        calls.borrow_mut().clear();

        // A change the system refuses: the file is never written.
        assert_eq!(save_in_step(false, true, set(false), write(true)), Err(AUTOSTART_REFUSED));
        assert_eq!(calls.borrow().as_slice(), ["startup true"]);
        calls.borrow_mut().clear();

        // A change that works, then a file that works.
        assert_eq!(save_in_step(false, true, set(true), write(true)), Ok("saved"));
        assert_eq!(calls.borrow().as_slice(), ["startup true", "write"]);
        calls.borrow_mut().clear();

        // A change that works, then a file that refuses: startup goes back to what it was.
        assert_eq!(save_in_step(true, false, set(true), write(false)), Err(SAVE_REFUSED));
        assert_eq!(calls.borrow().as_slice(), ["startup false", "write", "startup true"]);
        calls.borrow_mut().clear();

        // A file that refuses with no startup change: nothing to put back.
        assert_eq!(save_in_step(false, false, set(true), write(false)), Err(SAVE_REFUSED));
        assert_eq!(calls.borrow().as_slice(), ["write"]);
        calls.borrow_mut().clear();

        // The system takes the change but refuses to put it back: still the save sentence, and the log says both.
        let first_only = std::cell::Cell::new(true);
        let result = save_in_step(true, false, |_| first_only.replace(false), write(false));
        assert_eq!(result, Err(SAVE_REFUSED));
        let logged = crate::log::CAPTURED.lock().unwrap().iter().filter(|l| l.contains("Launch at startup") || l.contains("settings.json could not be saved")).cloned().collect::<Vec<_>>();
        assert!(logged.iter().any(|l| l == "settings.json could not be saved (PermissionDenied)"), "{logged:?}");
        assert!(logged.iter().any(|l| l == "Launch at startup could not be put back"), "{logged:?}");
        assert!(logged.iter().all(|l| !l.contains('/') && !l.contains('\\')), "{logged:?}");
    }

    /// A save with no file yet creates it, and nothing else.
    #[test]
    fn a_save_creates_a_file_that_is_not_there_yet() {
        let dir = scratch("save-new");
        let path = dir.join("settings.json");
        save_with(&AtomicBool::new(false), &path, &Settings::default(), rename_over).expect("written");
        assert!(path.exists());
        assert_eq!(names(&dir), vec!["settings.json".to_string()]);
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// A scratch folder of the test's own: removed first, created empty.
    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("notchmeow-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    /// The names in a folder, sorted: a test checks that nothing was added or moved.
    fn names(dir: &Path) -> Vec<String> {
        let mut found: Vec<String> = std::fs::read_dir(dir).unwrap().map(|e| e.unwrap().file_name().to_string_lossy().into_owned()).collect();
        found.sort();
        found
    }

    /// A rename and a copy that both fail, as on a folder the app may not write to.
    fn no_move(_: &Path, _: &Path) -> std::io::Result<()> {
        Err(std::io::Error::from(std::io::ErrorKind::PermissionDenied))
    }
    fn no_copy(_: &Path, _: &Path) -> std::io::Result<u64> {
        Err(std::io::Error::from(std::io::ErrorKind::PermissionDenied))
    }

    const BROKEN: &str = r#"{"soundEnabled": tru, "secretNote": "hand-typed"}"#;
    const VALID: &str = r#"{"soundEnabled":true,"soundVolume":0.12,"autoCloseInterval":15,"absenceInterval":180,
        "activeIntegrations":[],"screen":"cursor","autostart":false,"hooksInstalled":false}"#;

    /// A file that is not there is the first run, not a problem.
    #[test]
    fn a_missing_settings_file_is_the_first_run_and_no_problem() {
        let dir = scratch("missing-settings");
        let (s, problem) = checked(&dir.join("settings.json"));
        assert_eq!(problem, None);
        assert!(s.sound_enabled && s.screen == "primary", "defaults load");
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// A folder where the file should be: reading it fails with an error that is not "not found". Defaults load, and nothing is moved or written.
    #[test]
    fn a_settings_file_that_cannot_be_read_is_a_problem_and_is_left_where_it_is() {
        let dir = scratch("unreadable-settings");
        let path = dir.join("settings.json");
        std::fs::create_dir_all(&path).unwrap();
        let (s, problem) = checked(&path);
        assert_eq!(problem, Some(LoadProblem::Unreadable));
        assert!(s.sound_enabled && s.screen == "primary", "defaults load");
        assert!(path.is_dir(), "nothing is moved aside or written over");
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// The problem names the backup's file name only: never its content, never a path.
    #[test]
    fn an_unparseable_settings_file_names_its_backup_and_never_its_content() {
        let dir = scratch("unparseable-settings");
        let path = dir.join("settings.json");
        std::fs::write(&path, BROKEN).unwrap();
        let (s, problem) = checked(&path);
        assert!(s.sound_enabled && s.screen == "primary", "defaults load");
        let Some(LoadProblem::Unparseable { kept_as }) = problem.clone() else { panic!("{problem:?}") };
        assert!(kept_as.starts_with("settings.json.bad-") && !kept_as.contains('/') && !kept_as.contains('\\'), "{kept_as}");
        assert!(dir.join(&kept_as).exists(), "the backup is there");
        let json = serde_json::to_string(&problem).unwrap();
        assert!(!json.contains("hand-typed") && !json.contains(&*dir.to_string_lossy()), "{json}");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_valid_settings_file_is_no_problem() {
        let dir = scratch("valid-settings");
        let path = dir.join("settings.json");
        std::fs::write(&path, VALID).unwrap();
        let (s, problem) = checked(&path);
        assert_eq!(problem, None);
        assert_eq!(s.screen, "cursor");
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// Notepad's byte order mark is taken off before the parse, so a file it saved loads as any other, at boot and on a retry alike.
    #[test]
    fn a_settings_file_with_a_utf8_byte_order_mark_loads_at_boot_and_on_a_retry() {
        let dir = scratch("bom-settings");
        let path = dir.join("settings.json");
        let mut bytes = vec![0xEF, 0xBB, 0xBF];
        bytes.extend_from_slice(VALID.as_bytes());
        std::fs::write(&path, bytes).unwrap();
        let (boot, problem) = checked(&path);
        assert_eq!(problem, None, "a BOM is not a broken file");
        assert_eq!(boot.screen, "cursor");
        let (retry, problem) = read_only_at(&path);
        assert_eq!(problem, None, "read only, the same");
        assert_eq!(retry.screen, boot.screen);
        assert_eq!(names(&dir), vec!["settings.json".to_string()], "nothing is kept");
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// An empty file does not parse. At boot it is kept as a backup; read only, nothing is kept, so it is one that cannot be read (saves refused).
    #[test]
    fn an_empty_settings_file_is_kept_at_boot_and_unreadable_read_only() {
        let dir = scratch("empty-settings");
        let path = dir.join("settings.json");
        std::fs::write(&path, "").unwrap();
        let (_, read_only) = read_only_at(&path);
        assert_eq!(read_only, Some(LoadProblem::Unreadable));
        assert_eq!(names(&dir), vec!["settings.json".to_string()], "the read only moved nothing");
        let (_, boot) = checked(&path);
        assert!(matches!(boot, Some(LoadProblem::Unparseable { .. })), "{boot:?}");
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// A retry (or Start fresh's read) of a broken file adds no file and moves none: the boot already kept the copy.
    #[test]
    fn a_read_only_retry_of_an_unparseable_file_creates_no_file() {
        let dir = scratch("retry-unparseable");
        let path = dir.join("settings.json");
        std::fs::write(&path, BROKEN).unwrap();
        let before = names(&dir);
        let (s, problem) = read_only_at(&path);
        assert!(s.sound_enabled, "defaults");
        assert_eq!(problem, Some(LoadProblem::Unreadable), "a retry does not succeed on a file that does not parse");
        assert_eq!(names(&dir), before, "no copy, no move");
        assert!(std::fs::read_to_string(&path).unwrap().contains("hand-typed"), "the file is untouched");
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// A broken file that can be neither moved nor copied stays in place and is `Unreadable` at boot, exactly as a read only finds it, so Start fresh can clear it.
    #[test]
    fn an_unkeepable_unparseable_file_is_unreadable_at_boot_and_read_only_alike() {
        let dir = scratch("unkeepable");
        let path = dir.join("settings.json");
        std::fs::write(&path, BROKEN).unwrap();
        let (_, boot) = load_checked_with(&path, no_move, no_copy);
        assert_eq!(boot, Some(LoadProblem::Unreadable));
        let (_, now) = read_only_at(&path);
        assert_eq!(now, Some(LoadProblem::Unreadable));
        assert_eq!(names(&dir), vec!["settings.json".to_string()], "the file stays where it is");
        assert_eq!(start_fresh_refusal(&boot, &now, true), None, "Start fresh clears it: the banner promised it works");
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// A copy that fails part-way leaves no partial backup behind, and the file is then one that cannot be read (saves refused).
    #[test]
    fn a_backup_copy_that_fails_part_way_is_removed() {
        let dir = scratch("partial-copy");
        let path = dir.join("settings.json");
        std::fs::write(&path, BROKEN).unwrap();
        let partial_copy = |_: &Path, to: &Path| -> std::io::Result<u64> {
            std::fs::write(to, b"partial")?;
            Err(std::io::Error::from(std::io::ErrorKind::StorageFull))
        };
        let (_, problem) = load_checked_with(&path, no_move, partial_copy);
        assert_eq!(problem, Some(LoadProblem::Unreadable));
        assert_eq!(names(&dir), vec!["settings.json".to_string()], "the partial copy is gone");
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// Only an unreadable file refuses saves: a file that did not parse was kept as a backup, so it may be written over.
    #[test]
    fn saves_are_refused_only_while_the_file_is_unreadable() {
        assert!(!save_allowed(&Some(LoadProblem::Unreadable)));
        assert!(save_allowed(&Some(LoadProblem::Unparseable { kept_as: "settings.json.bad-1".into() })));
        assert!(save_allowed(&None));
    }

    /// Start fresh clears the refusal only for a file that was unreadable at boot and still cannot be read; otherwise it says why, in one of three sentences.
    #[test]
    fn start_fresh_says_why_it_refuses_in_one_of_three_sentences() {
        let unreadable = Some(LoadProblem::Unreadable);
        let broken = Some(LoadProblem::Unparseable { kept_as: "settings.json.bad-1".into() });
        assert_eq!(start_fresh_refusal(&unreadable, &unreadable, true), None);
        assert_eq!(start_fresh_refusal(&unreadable, &None, false), Some("There is no settings file to replace; use Try again."));
        assert_eq!(start_fresh_refusal(&unreadable, &None, true), Some("Your settings file can be read now; use Try again."));
        assert_eq!(start_fresh_refusal(&broken, &None, true), Some("Your settings file can be read now; use Try again."));
        assert_eq!(start_fresh_refusal(&None, &unreadable, true), Some("Your settings file still couldn't be read."));
    }

    /// An unparseable file at boot (a backup exists) is not one Start fresh replaces: it is refused even while it still does not parse.
    #[test]
    fn start_fresh_is_refused_after_an_unparseable_boot() {
        let dir = scratch("unparseable-boot");
        let path = dir.join("settings.json");
        std::fs::write(&path, BROKEN).unwrap();
        let (_, boot) = checked(&path);
        assert!(matches!(boot, Some(LoadProblem::Unparseable { .. })));
        std::fs::write(&path, BROKEN).unwrap();
        let (_, now) = read_only_at(&path);
        assert_eq!(start_fresh_refusal(&boot, &now, true), Some("Your settings file still couldn't be read."));
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// The gate is the save's own check: a refused save writes nothing and names no path; an open gate writes the file. The gate and the folder are the test's own.
    #[test]
    fn a_refused_save_writes_nothing_and_an_open_gate_writes_the_file() {
        let dir = scratch("save-gate");
        let path = dir.join("settings.json");
        let blocked = AtomicBool::new(true);
        let refused = save_with(&blocked, &path, &Settings::default(), rename_over).expect_err("refused while blocked");
        assert!(!path.exists(), "nothing is written");
        assert!(!refused.to_string().contains(&*dir.to_string_lossy()), "{refused}");
        blocked.store(false, Ordering::SeqCst);
        save_with(&blocked, &path, &Settings::default(), rename_over).expect("written once the gate is open");
        assert!(path.exists());
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// The page reads the problem as `{ kind, keptAs }`, camelCase, and nothing else.
    #[test]
    fn the_problem_is_sent_to_the_page_as_kind_and_kept_as() {
        assert_eq!(serde_json::to_value(LoadProblem::Unreadable).unwrap(), serde_json::json!({ "kind": "unreadable" }));
        let unparseable = LoadProblem::Unparseable { kept_as: "settings.json.bad-1".into() };
        assert_eq!(
            serde_json::to_value(unparseable).unwrap(),
            serde_json::json!({ "kind": "unparseable", "keptAs": "settings.json.bad-1" })
        );
    }
}
