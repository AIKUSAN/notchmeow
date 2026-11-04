// NotchMeow for Windows — app wiring and the commands the island calls.

mod agent_hooks;
mod ai;
mod cat_settings;
#[cfg_attr(not(windows), allow(dead_code))]
mod claude_app;
mod desktop;
mod dragout;
mod files;
mod foreground;
mod hooks;
mod integrations;
mod island;
pub mod link;
mod link_cmd;
mod log;
mod pipe;
mod platform;
mod pointer;
mod secrets;
mod settings;
mod sidekick;
mod sidekick_presence;
mod sidekick_settings;
mod companion_settings;
mod companion_store;
mod shelf;
mod tray;
#[cfg(test)]
mod testenv;

use std::process::Command;
use std::sync::atomic::Ordering;
use std::sync::{Arc, Mutex};

use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager, State, WebviewUrl, WebviewWindowBuilder};
use tauri_plugin_autostart::{ManagerExt, MacosLauncher};

use agent_hooks::Agent;
use files::DroppedFile;
use hooks::{HookPreview, HookStatus};
use island::{PollGate, ScreenInfo};
use pipe::Pending;
use settings::Settings;

pub struct Shared {
    pub settings: Mutex<Settings>,
    /// What stopped the file from loading at start-up, until Start fresh or a successful Try again clears it.
    pub settings_problem: Mutex<Option<settings::LoadProblem>>,
    pub gate: Arc<PollGate>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BootInfo {
    settings: Settings,
    screen: ScreenInfo,
    version: String,
    hook_path: String,
    /// False where the OS has no global cursor (Wayland): the page then reports
    /// the cursor from its own mouse events.
    cursor_poll: bool,
    /// False where the system places windows itself (GNOME): Settings says so under the desktop cat's switch.
    desktop_positioned: bool,
    /// The user's home folder: the Sidekick reads `~` and `$HOME` in a request's path against it. It is never shown, logged or sent anywhere.
    home: String,
    /// What the shelf can do on this system: drag a file out of the island, send it through the system's share.
    shelf: ShelfCaps,
    /// There is a Claude desktop app the pill's Open can start (Windows). Anthropic ships none for Linux.
    claude_app: bool,
    /// Which foreground read this system has for focus awareness: "windows", "x11" or "none" (Wayland).
    foreground: &'static str,
    /// Why the settings file could not be used at start-up (`null` when it could). The page shows it above the column until the person chooses.
    settings_problem: Option<settings::LoadProblem>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ShelfCaps {
    drag_out: bool,
    send: bool,
}

#[tauri::command]
fn boot(app: AppHandle, shared: State<Shared>) -> BootInfo {
    let mut settings = shared.settings.lock().unwrap().clone();
    // The real state of ~/.claude/settings.json wins over whatever we stored.
    settings.hooks_installed = hooks::status().installed;
    let screen = island::screen_info(&app, &settings.screen);
    BootInfo {
        settings,
        screen,
        version: env!("CARGO_PKG_VERSION").to_string(),
        hook_path: settings::hook_exe_path().to_string_lossy().to_string(),
        cursor_poll: platform::pointer_feed(),
        desktop_positioned: platform::desktop_positioned(),
        home: platform::home_dir().to_string_lossy().to_string(),
        shelf: ShelfCaps { drag_out: dragout::supported(), send: platform::SHARE },
        claude_app: platform::CLAUDE_APP,
        foreground: foreground::kind(cfg!(windows), platform::pointer_feed()),
        settings_problem: shared.settings_problem.lock().unwrap().clone(),
    }
}

/// Clears the problem and opens the save gate: the one place a problem is taken away.
fn clear_problem(shared: &Shared) {
    *shared.settings_problem.lock().unwrap() = None;
    settings::set_save_gate(&None);
}

/// The log line for an event that could not be sent: the event's name (a fixed word of ours) and nothing else, never the value.
fn emit_failure_line(event: &str) -> String {
    format!("could not send the {event} event")
}

/// Tells the Settings window (or the island, for a shared event) of a change. A failed emit is logged in a fixed sentence that names the event: never the value.
pub(crate) fn logged_emit(event: &str, result: tauri::Result<()>) {
    if result.is_err() {
        log::line(emit_failure_line(event));
    }
}

/// Moves the island to the display the settings name, when it is another one than before. Shared by a save and by Try again.
fn apply_screen_change(app: &AppHandle, shared: &Shared, previous: &str, now: &str) {
    if previous != now {
        let collapsed = shared.gate.collapsed.load(Ordering::Relaxed);
        island::apply_geometry(app, now, collapsed);
    }
}

/// Try again: the file is read once more, without moving or copying anything. A read that works replaces the shared settings and clears the problem, emits
/// `settings-changed` and returns the settings. One that still fails is refused in a fixed sentence, and nothing changes.
#[tauri::command]
fn settings_retry_load(app: AppHandle, shared: State<Shared>) -> Result<Settings, String> {
    let (mut loaded, problem) = settings::load_checked_read_only();
    if problem.is_some() {
        return Err("Your settings file still couldn't be read.".into());
    }
    // The real state of ~/.claude/settings.json wins over whatever we stored, as at boot.
    loaded.hooks_installed = hooks::status().installed;
    let previous = std::mem::replace(&mut *shared.settings.lock().unwrap(), loaded.clone());
    clear_problem(&shared);
    // What was loaded may name another display than the defaults the island started on: it moves the way a save's would.
    apply_screen_change(&app, &shared, &previous.screen, &loaded.screen);
    logged_emit("settings-changed", app.emit("settings-changed", loaded.clone()));
    Ok(loaded)
}

/// Start fresh: the person accepts the defaults and saves work again. It clears the refusal only for a file that was unreadable at boot and still cannot be read
/// now; anything else is refused with the reason (`settings::start_fresh_refusal`). Nothing is written here: the next change replaces the unreadable file.
#[tauri::command]
fn settings_start_fresh(shared: State<Shared>) -> Result<(), String> {
    let current = shared.settings_problem.lock().unwrap().clone();
    let (_, now) = settings::load_checked_read_only();
    if let Some(refusal) = settings::start_fresh_refusal(&current, &now, settings::settings_file_exists()) {
        return Err(refusal.into());
    }
    clear_problem(&shared);
    Ok(())
}

#[tauri::command]
fn save_settings(app: AppHandle, shared: State<Shared>, settings: Settings) -> Result<(), String> {
    // What the webview sends is cleaned before it is stored, saved or shared: a server URL
    // loses any `user:pass@` (see `settings::sanitized`).
    let settings = settings::sanitized(settings);
    // "Launch at startup" is changed first and the file written after (`settings::save_in_step`): a refusal of either is told in a fixed sentence (no path, no system
    // text), and a refused file puts the startup change back. A failed write changes nothing: the shared copy and the screen stay as they were.
    let was = shared.settings.lock().unwrap().autostart;
    let previous = settings::save_in_step(
        was,
        settings.autostart,
        |on| {
            let manager = app.autolaunch();
            (if on { manager.enable() } else { manager.disable() }).is_ok()
        },
        || settings::commit(&shared.settings, settings.clone(), settings::save),
    )
    .map_err(String::from)?;
    apply_screen_change(&app, &shared, &previous.screen, &settings.screen);
    // Keep the other window in step (island ⇄ settings window).
    logged_emit("settings-changed", app.emit("settings-changed", settings));
    Ok(())
}

/// Hidden island → shrink the window to the invisible wake strip and park the
/// cursor poll; anything else → full panel and 60 Hz polling.
#[tauri::command]
fn set_collapsed(app: AppHandle, shared: State<Shared>, collapsed: bool) {
    let pref = shared.settings.lock().unwrap().screen.clone();
    shared.gate.collapsed.store(collapsed, Ordering::Relaxed);
    island::apply_geometry(&app, &pref, collapsed);
    // The wake strip must always take the mouse, and a resize invalidates the flag.
    island::refresh_click_through(&app, &shared.gate);
    shared.gate.set_active(!collapsed);
}

/// The front end pushes the island shape; Rust decides click-through from it.
#[tauri::command]
fn set_island_rect(app: AppHandle, shared: State<Shared>, x: f64, y: f64, width: f64, height: f64) {
    shared.gate.set_rect(island::IslandRect { x, y, w: width, h: height });
    // Without the cursor poll the input region is the click-through: it follows the island.
    if !platform::CURSOR_POLL {
        island::refresh_click_through(&app, &shared.gate);
    }
}

/// The outside click: the page turns the reading of the mouse buttons on while the island is expanded and off otherwise (island.rs, `pointer-button`). Off, the poll reads nothing extra.
#[tauri::command]
fn watch_pointer_buttons(shared: State<Shared>, on: bool) {
    shared.gate.watch_buttons.store(on, Ordering::Relaxed);
}

#[tauri::command]
fn focus_window(app: AppHandle, focused: bool) {
    let Some(win) = island::window(&app) else { return };
    platform::set_activating(&win, focused);
    if focused {
        let _ = win.set_focus();
    }
}

#[tauri::command]
fn reposition(app: AppHandle, shared: State<Shared>) {
    let pref = shared.settings.lock().unwrap().screen.clone();
    let collapsed = shared.gate.collapsed.load(Ordering::Relaxed);
    island::apply_geometry(&app, &pref, collapsed);
}

/// The panel is laid out in CSS px against the window's own scale. If the webview reports another devicePixelRatio, the page ends up wider than the window and
/// the island is cut: correct the webview's zoom so one CSS px is one logical px again. True when the zoom changed.
#[tauri::command]
fn fit_zoom(app: AppHandle, dpr: f64) -> bool {
    let Some(win) = island::window(&app) else { return false };
    let scale = win.scale_factor().unwrap_or(1.0);
    static ZOOM: Mutex<f64> = Mutex::new(1.0);
    let mut zoom = ZOOM.lock().unwrap();
    match island::calculate_zoom_correction(*zoom, scale, dpr) {
        Some(new_zoom) => {
            *zoom = new_zoom;
            log::line(format!("webview dpr {dpr} != window scale {scale}: zoom {new_zoom:.3}"));
            let _ = win.set_zoom(new_zoom);
            true
        }
        None => false,
    }
}

/// The addresses `open_url` hands to the system: `http://` or `https://` (lower case) and at least one character after it, at most 2,048 characters, and none of the characters that a command line, a markup
/// attribute or a URL parser could read as something else: whitespace (JavaScript's `\s` set, so the page's `WEB_URL` filter in companion/markdown.ts and this agree), controls
/// (U+0000 to U+001F and U+007F to U+009F) and `"` `<` `>` `\` `` ` `` `^` `|` `{` `}`. The length is counted in UTF-16 units, as the page's `url.length` counts it.
fn url_ok(url: &str) -> bool {
    (url.strip_prefix("http://").or_else(|| url.strip_prefix("https://"))).is_some_and(|rest| !rest.is_empty())
        && url.encode_utf16().count() <= 2048
        && !url.chars().any(|c| c.is_whitespace() || c == '\u{feff}' || c.is_control() || matches!(c, '"' | '<' | '>' | '\\' | '`' | '^' | '|' | '{' | '}'))
}

#[tauri::command]
fn open_url(url: String) {
    if !url_ok(&url) {
        return;
    }
    platform::open_url(&url);
}

/// "Open terminal" opens the working folder in VS Code when `code` is on PATH,
/// and falls back to the file manager otherwise.
#[tauri::command]
fn open_in_vscode(path: Option<String>) -> bool {
    // No shell anywhere near this. The path is a project folder chosen by
    // whoever is using Claude Code, and a shell would happily read `&`, `^`, `%`
    // or `$` in a folder name as syntax. Finding the launcher ourselves and
    // handing the path over as a separate argument keeps it a path.
    let path = path.filter(|p| !p.is_empty());
    // It arrives in a hook payload: only an existing folder, given by its full
    // path, goes any further. `code` would read `--something` as an option, and
    // xdg-open would launch a file with whatever handles its type.
    if let Some(p) = path.as_deref() {
        let p = std::path::Path::new(p);
        if !(p.is_absolute() && p.is_dir()) {
            return false;
        }
    }
    if let Some(code) = platform::find_on_path("code") {
        let mut cmd = Command::new(code);
        if let Some(p) = path.as_deref() {
            cmd.arg(p);
        }
        if platform::no_console(&mut cmd).spawn().is_ok() {
            return true;
        }
    }
    if let Some(p) = path.as_deref() {
        platform::reveal_folder(p);
    }
    false
}

/// The pill's Open for a Claude Code session from the Claude desktop app: starts the app (Windows), or brings it forward when it runs. False when it cannot be found, and always on Linux, where
/// Anthropic ships no desktop app. The lookup may start PowerShell, so it runs off the main thread.
#[tauri::command]
async fn open_claude_app() -> bool {
    blocking(platform::open_claude_app).await.unwrap_or(false)
}

/// Puts a text on the clipboard: the paths of the files dropped on an agent's cat (the Sidekick, on one line). It fills the clipboard and nothing else: no paste, no keystroke, no other
/// program is touched. A text that is empty, too long or has a NUL is refused.
#[tauri::command]
fn copy_text(app: AppHandle, text: String) -> bool {
    sidekick_presence::clipboard_text_ok(&text) && platform::copy_text(&app, &text)
}

#[tauri::command]
fn quit_app(app: AppHandle) {
    app.exit(0);
}

/// Tray → Pause. Paused means paused: the pollers stop talking to the network,
/// not just the island stopping showing things.
#[tauri::command]
fn set_paused(paused: bool) {
    integrations::set_paused(paused);
}

// ── Claude Code hooks ─────────────────────────────────────────────────────────

#[tauri::command]
fn hooks_status() -> HookStatus {
    hooks::status()
}

/// Returns the diff the user has to look at before anything is written.
#[tauri::command]
fn hooks_preview(install: bool) -> Result<HookPreview, String> {
    hooks::preview(install)
}

/// Only ever called from an explicit click in the settings window.
#[tauri::command]
fn hooks_apply(
    app: AppHandle,
    shared: State<Shared>,
    install: bool,
    fingerprint: String,
) -> Result<String, String> {
    // The fingerprint comes from the preview the user actually looked at, so a
    // settings.json that changed in between is refused rather than overwritten.
    let backup = hooks::write(install, &fingerprint)?;
    // The hook files are written either way. The shared copy and the window hear of the flag only once settings.json holds it.
    let change = |s: &mut Settings| {
        let changed = s.hooks_installed != install;
        s.hooks_installed = install;
        changed
    };
    match settings::update(&shared.settings, change, settings::save) {
        Ok(Some(updated)) => logged_emit("settings-changed", app.emit("settings-changed", updated)),
        Ok(None) => {}
        Err(_) => crate::log::line("settings.json could not be saved"),
    }
    Ok(backup)
}

// ── Gemini CLI and Antigravity hooks ──────────────────────────────────────────
// The same three steps as Claude Code's, for the agent the settings window names
// (`gemini` or `antigravity`; anything else is refused).

#[tauri::command]
fn agent_hooks_status(agent: String) -> Result<HookStatus, String> {
    Ok(agent_hooks::status(Agent::from_tag(&agent)?))
}

#[tauri::command]
fn agent_hooks_preview(agent: String, install: bool) -> Result<HookPreview, String> {
    agent_hooks::preview(Agent::from_tag(&agent)?, install)
}

/// Only ever called from an explicit click in the settings window.
#[tauri::command]
fn agent_hooks_apply(agent: String, install: bool, fingerprint: String) -> Result<String, String> {
    agent_hooks::write(Agent::from_tag(&agent)?, install, &fingerprint)
}

#[tauri::command]
fn approval_decision(app: AppHandle, request_id: String, decision: String) {
    pipe::answer(&app, &request_id, &decision);
}

/// The island has the card on screen, so the long wait for a human may begin.
/// Until this arrives the relay only waits a few hundred milliseconds, which is
/// what stops a paused or unresponsive island from freezing Claude Code.
#[tauri::command]
fn approval_ack(app: AppHandle, request_id: String) {
    pipe::acknowledge(&app, &request_id);
}

/// Nobody can act on this request — the island is paused, or another card is
/// already up. Claude Code falls back to asking in the terminal immediately.
#[tauri::command]
fn approval_decline(app: AppHandle, request_id: String) {
    pipe::decline(&app, &request_id);
}

/// The foreground app's process image name (Windows) or window class (Linux under X11), read once for one permission request (focus awareness). Compared by the page and
/// dropped: never logged, stored or sent anywhere. None where it cannot be read (Wayland, our own window, a failed read).
#[tauri::command]
async fn foreground_app(app: AppHandle) -> Option<String> {
    blocking(move || platform::foreground_app(&app)).await.ok().flatten()
}

// ── Chat, files and secrets ───────────────────────────────────────────────────

/// A new conversation: a file was dropped or the chat was cleared. A reply still
/// on its way is stopped and dropped.
#[tauri::command]
fn chat_reset(ai: State<ai::AiState>) {
    ai.reset();
}

/// Copies a dropped file into the inbox and reports its name back.
#[tauri::command]
fn ingest_file(path: String) -> Result<DroppedFile, String> {
    files::ingest(&path)
}

/// A pasted screenshot: the PNG's bytes arrive as the raw body of the invoke (no JSON, no base64) and go to the inbox like a dropped file. Anything
/// that is not raw bytes is refused, and the bytes are never logged.
#[tauri::command]
async fn ingest_png(request: tauri::ipc::Request<'_>) -> Result<DroppedFile, String> {
    let tauri::ipc::InvokeBody::Raw(bytes) = request.body() else {
        return Err("That isn't a picture NotchMeow can read.".into());
    };
    let bytes = bytes.clone();
    blocking(move || files::ingest_png(&bytes)).await?
}

/// The drag-out spike (Debug builds only): makes a small text file of its own and drags it out of the island, so a person can try dropping it in Explorer, the file manager or a mail
/// window on a real machine. Release builds refuse. The shelf's own drag out is `shelf_drag_out`.
#[tauri::command]
async fn drag_out_spike(app: AppHandle) -> Result<&'static str, String> {
    if !cfg!(debug_assertions) {
        return Err("The drag-out spike is a Debug-build tool.".into());
    }
    let dir = settings::local_dir().join("spike");
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    let file = dir.join("NotchMeow drag test.txt");
    std::fs::write(&file, "Dragged out of the NotchMeow island.\n").map_err(|e| e.to_string())?;
    dragout::start(&app, vec![file]).await
}

// ── The shelf (sub-project G1) ────────────────────────────────────────────────
// The page holds ids, never paths: every command that touches a file takes an id and Rust finds the file. They run off the main thread, because looking at the files of a
// shelf (a network drive that went away) can take a while.

fn shelf_store() -> shelf::Store {
    shelf::Store::new(settings::local_dir())
}

async fn blocking<T: Send + 'static>(work: impl FnOnce() -> T + Send + 'static) -> Result<T, String> {
    tauri::async_runtime::spawn_blocking(work).await.map_err(|e| e.to_string())
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ShelfAdded {
    entries: Vec<shelf::Entry>,
    /// One word per dropped path: `added`, `duplicate`, `full` or `invalid`.
    results: Vec<&'static str>,
}

/// The shelf as it opens, each item with whether its original is gone (the only time the files are looked at).
#[tauri::command]
async fn shelf_list() -> Result<Vec<shelf::Entry>, String> {
    blocking(|| shelf_store().entries()).await
}

#[tauri::command]
async fn shelf_add(paths: Vec<String>) -> Result<ShelfAdded, String> {
    let (entries, results) = blocking(move || shelf_store().add_paths(&paths)).await?.map_err(|e| e.to_string())?;
    Ok(ShelfAdded { entries, results })
}

#[tauri::command]
async fn shelf_remove(id: String) -> Result<Vec<shelf::Entry>, String> {
    blocking(move || shelf_store().remove(&id)).await?.map_err(|e| e.to_string())
}

#[tauri::command]
async fn shelf_clear() -> Result<Vec<shelf::Entry>, String> {
    blocking(|| shelf_store().clear()).await?.map_err(|e| e.to_string())
}

/// Drag out of the island: Rust finds the files from the ids (the page holds no path), and a native drag source (dragout.rs) carries them until the user lets go.
/// Resolves with `copied`, `none` or `cancelled`.
#[tauri::command]
async fn shelf_drag_out(app: AppHandle, ids: Vec<String>) -> Result<&'static str, String> {
    let paths = blocking(move || shelf_store().resolve(&ids)).await?;
    dragout::start(&app, paths).await
}

/// Show in Explorer or the file manager, with the file selected. One item: its id, and Rust finds the file.
#[tauri::command]
async fn shelf_reveal(id: String) -> Result<(), String> {
    blocking(move || {
        let path = shelf_store().resolve(&[id]).into_iter().next().ok_or_else(|| "That file is gone.".to_string())?;
        platform::reveal_file(&path);
        Ok(())
    })
    .await?
}

/// Send: the system's Share window (Windows) opens over the island with these items. Always started by a click; nothing but the fact that a send started is logged.
#[tauri::command]
async fn shelf_send(app: AppHandle, ids: Vec<String>) -> Result<(), String> {
    if !platform::SHARE {
        return Err("There is no system share on this system.".into());
    }
    let win = island::window(&app).ok_or_else(|| "The island window is not there.".to_string())?;
    blocking(move || {
        let paths = shelf_store().resolve(&ids);
        if paths.is_empty() {
            return Err("Those files are gone.".to_string());
        }
        log::line("shelf send started");
        platform::share_files(&win, &paths)
    })
    .await?
}

/// Ask: the shelf item goes into the inbox like a file dropped on Ask (the same screening, the same copy), and the page starts a new chat with it.
#[tauri::command]
async fn shelf_ask(id: String) -> Result<DroppedFile, String> {
    blocking(move || {
        let path = shelf_store().resolve(&[id]).into_iter().next().ok_or_else(|| "That file is gone.".to_string())?;
        // ingest puts the full source path into its read errors; the page gets a fixed line instead. Other messages (a folder, a screened file) pass through.
        files::ingest(&path.to_string_lossy()).map_err(|e| if e.starts_with("cannot read ") { "cannot read the file".to_string() } else { e })
    })
    .await?
}

/// The island may only ask whether a key exists — never read it. The store can be slow (a keyring waiting to be unlocked), so it is asked off the main thread; a
/// task that did not come back is "no".
#[tauri::command]
async fn secret_present(key: String) -> bool {
    blocking(move || secrets::present(&key)).await.unwrap_or(false)
}

/// The Settings window asks for the three-way presence; the island keeps `secret_present`. Off the main thread like it; a task that did not come back is unreadable.
#[tauri::command]
async fn secret_presence(key: String) -> secrets::Presence {
    blocking(move || secrets::presence(&key)).await.unwrap_or(secrets::Presence::Unreadable)
}

#[tauri::command]
fn secret_set(ai: State<ai::AiState>, key: String, value: String) -> Result<(), String> {
    let saved = secrets::logged("set", &key, secrets::set(&key, &value));
    // A key changed: the model chip and Auto must look at the keychain again.
    ai.forget_key_presence();
    saved
}

#[tauri::command]
fn secret_clear(ai: State<ai::AiState>, key: String) -> Result<(), String> {
    let removed = secrets::logged("clear", &key, secrets::clear(&key));
    ai.forget_key_presence();
    removed
}

/// Opens the configured n8n instance — the URL lives in the Credential Manager.
#[tauri::command]
fn open_n8n() {
    if let Some(url) = secrets::get("n8n-url") {
        open_url(url);
    }
}

/// Refresh buttons in the integration cards.
#[tauri::command]
async fn refresh_integration(app: AppHandle, id: String) {
    integrations::poll_once(app, &id).await;
}

// ── The companion's conversations (sub-project F3a-tauri) ────────────────────
// The page holds ids and records cleaned by conversationClean; Rust holds the files. They run off the main thread, as the shelf's do. A refusal is one fixed sentence
// and the log gets a fixed sentence too: never a record, a path or OS text.

fn conversations() -> companion_store::Store {
    companion_store::Store::new(companion_store::companion_dir().join("conversations"))
}

#[tauri::command]
async fn companion_list() -> Vec<companion_store::Head> {
    blocking(|| conversations().list()).await.unwrap_or_default()
}

#[tauri::command]
async fn companion_load(id: String) -> Option<serde_json::Value> {
    blocking(move || conversations().load(&id)).await.unwrap_or(None)
}

#[tauri::command]
async fn companion_save(record: serde_json::Value) -> Result<(), String> {
    let saved = blocking(move || conversations().save(&record)).await.map_err(|_| companion_store::SAVE_FAILED.to_string())?;
    saved.map_err(|fixed| {
        log::line("companion: a conversation was not saved");
        fixed.to_string()
    })
}

#[tauri::command]
async fn companion_delete(id: String) -> Result<(), String> {
    let deleted = blocking(move || conversations().delete(&id)).await.map_err(|_| companion_store::DELETE_FAILED.to_string())?;
    deleted.map_err(|fixed| {
        log::line("companion: a conversation was not deleted");
        fixed.to_string()
    })
}

#[tauri::command]
async fn companion_delete_all(app: tauri::AppHandle, ai: State<'_, ai::AiState>) -> Result<usize, String> {
    let (removed, outcome) = blocking(|| conversations().delete_all_counting()).await.map_err(|_| companion_store::DELETE_FAILED.to_string())?;
    // A file that went is gone whatever came after it: What the AI saw last goes, and every window is told, so each open chat forgets its id
    // (companion/session.ts forgetDeletedAll). A delete that removed nothing announces nothing. The page still gets the error when there was one.
    if companion_store::announces(removed) {
        ai::forget_sent(&ai.sent);
        logged_emit("companion-deleted-all", app.emit("companion-deleted-all", ()));
    }
    outcome.map(|()| removed).map_err(|fixed| {
        log::line("companion: the conversations were not all deleted");
        fixed.to_string()
    })
}

/// Lets the island write to the same log as the Rust side.
#[tauri::command]
fn log_line(message: String) {
    log::line(format!("ui  {message}"));
}

// ── Settings window ───────────────────────────────────────────────────────────

/// WebView2 allows exactly one browser environment per app, and its options are
/// fixed by whichever webview is created first. Every window must therefore ask
/// for the *same* arguments as the island (see `additionalBrowserArgs` in
/// tauri.conf.json) — a mismatch makes the second window come up blank, with no
/// error anywhere.
pub(crate) const BROWSER_ARGS: &str = "--disable-features=msWebOOUI,msPdfOOUI,msSmartScreenProtection --autoplay-policy=no-user-gesture-required";

/// In a dev build the pages are served by Vite, so the second window needs the
/// absolute dev URL; a bundled build resolves it inside the app bundle.
fn settings_page_url(app: &AppHandle) -> WebviewUrl {
    #[cfg(dev)]
    if let Some(mut base) = app.config().build.dev_url.clone() {
        base.set_path("/settings.html");
        return WebviewUrl::External(base);
    }
    let _ = app;
    WebviewUrl::App("settings.html".into())
}

/// The settings window is created hidden at launch and only ever shown and
/// hidden afterwards. A WebView2 window created later — on the main thread or
/// not — silently comes up blank in this app, so the window that works is the
/// one that exists before the island's webview does.
fn create_settings_window(app: &AppHandle) {
    let url = settings_page_url(app);
    match WebviewWindowBuilder::new(app, "settings", url)
        .additional_browser_args(BROWSER_ARGS)
        .title("Settings — NotchMeow")
        .inner_size(720.0, 560.0)
        .min_inner_size(415.0, 420.0)
        .resizable(true)
        .visible(false)
        .center()
        .build()
    {
        Ok(win) => {
            // Closing it must only hide it, or it could never be reopened.
            let hidden = win.clone();
            let app = app.clone();
            win.on_window_event(move |event| {
                if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                    api.prevent_close();
                    let _ = hidden.hide();
                    // The next open reads the added server's key from the keychain again.
                    app.state::<ai::AiState>().forget_custom_key();
                    // Settings → Devices is no longer on screen, whatever the page last said: Rust is the one that knows the window went away.
                    link_cmd::settings_hidden(&app);
                    // The page drops what was typed and not saved (the restyle spec's rule 11): the window is only hidden, so it never reloads.
                    logged_emit("settings-hidden", app.emit_to("settings", "settings-hidden", ()));
                }
            });
        }
        Err(err) => log::line(format!("settings window failed: {err}")),
    }
}

pub fn show_settings_window(app: &AppHandle) {
    let Some(win) = app.get_webview_window("settings") else {
        log::line("settings window missing");
        return;
    };
    let _ = win.unminimize();
    let _ = win.show();
    let _ = win.set_focus();
}

/// The Settings place the island asks for (`devices`, `chat/keys`): lower-case letters and at most one slash; anything else is dropped, and the window opens where it was. The page reads it through `migrate`.
fn settings_place(raw: Option<String>) -> Option<String> {
    let place = raw?;
    if place.len() > 32 {
        return None;
    }
    let word = |s: &str| !s.is_empty() && s.bytes().all(|b| b.is_ascii_lowercase());
    let ok = match place.split_once('/') {
        Some((page, tab)) => word(page) && word(tab),
        None => word(&place),
    };
    ok.then_some(place)
}

#[tauri::command]
fn open_settings_window(app: AppHandle, place: Option<String>) {
    show_settings_window(&app);
    let asked = place.is_some();
    match settings_place(place) {
        Some(p) => logged_emit("settings-place", app.emit_to("settings", "settings-place", p)),
        None if asked => log::line("Settings place was not a page"),
        None => {}
    }
}

// ── Chat window ───────────────────────────────────────────────────────────────

/// The chat's own window (the pop-out). Made hidden at launch for the same reason as the settings window, and only ever shown and hidden afterwards; its page does nothing
/// until it is shown. Nothing here logs a message, an id or a path.
pub(crate) const CHAT_LABEL: &str = "chat";

fn chat_page_url(app: &AppHandle) -> WebviewUrl {
    #[cfg(dev)]
    if let Some(mut base) = app.config().build.dev_url.clone() {
        base.set_path("/chat.html");
        return WebviewUrl::External(base);
    }
    let _ = app;
    WebviewUrl::App("chat.html".into())
}

/// Tells the island's page that the chat window is gone (closed, or sent away): it takes the chat back.
fn chat_hidden(app: &AppHandle) {
    logged_emit("chat-window-hidden", app.emit_to(island::WINDOW_LABEL, "chat-window-hidden", ()));
}

fn create_chat_window(app: &AppHandle) {
    let url = chat_page_url(app);
    match WebviewWindowBuilder::new(app, CHAT_LABEL, url)
        .additional_browser_args(BROWSER_ARGS)
        .title("Chat — NotchMeow")
        .inner_size(520.0, 640.0)
        .min_inner_size(420.0, 360.0)
        .resizable(true)
        .visible(false)
        .center()
        .build()
    {
        Ok(win) => {
            // Closing it only hides it, or it could never be shown again; the island is told so it takes the chat back.
            let hidden = win.clone();
            let app = app.clone();
            win.on_window_event(move |event| {
                if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                    api.prevent_close();
                    let _ = hidden.hide();
                    chat_hidden(&app);
                }
            });
        }
        Err(err) => log::line(format!("chat window failed: {err}")),
    }
}

/// The only ids the window is told to open: the contract's conversation id, else the window starts a new chat.
fn chat_open_id(id: Option<String>) -> Option<String> {
    id.filter(|s| companion_store::is_id(s))
}

/// Where a relayed message may go: the island's page or the chat window's, by the names the pages use.
fn chat_target(to: &str) -> Option<&'static str> {
    match to {
        "island" => Some(island::WINDOW_LABEL),
        "chat" => Some(CHAT_LABEL),
        _ => None,
    }
}

/// Shows the chat window (unminimized, in front). A window that was hidden is told which conversation to open (`null`: a new chat) and loads it from its file; one that was already
/// showing is only brought forward, because what it holds may be newer than anything the island knows (the island's chat tab asks again while it is out).
#[tauri::command]
fn show_chat_window(app: AppHandle, conversation_id: Option<String>) -> Result<(), String> {
    let Some(win) = app.get_webview_window(CHAT_LABEL) else {
        log::line("chat window missing");
        return Err("The chat window isn't available.".into());
    };
    let was_showing = win.is_visible().unwrap_or(false);
    let _ = win.unminimize();
    // A window that would not show is said so: the page keeps the island open and its chat where it was.
    if win.show().is_err() {
        log::line("chat window failed to show");
        return Err(CHAT_SHOW_FAILED.into());
    }
    let _ = win.set_focus();
    if !was_showing {
        logged_emit("chat-window-open", app.emit_to(CHAT_LABEL, "chat-window-open", serde_json::json!({ "conversationId": chat_open_id(conversation_id) })));
    }
    Ok(())
}

#[tauri::command]
fn hide_chat_window(app: AppHandle) {
    if let Some(win) = app.get_webview_window(CHAT_LABEL) {
        let _ = win.hide();
    }
    chat_hidden(&app);
}

/// The largest message the chat sends between its two pages: 256 KiB as JSON. A bigger one is refused and never passed on.
const RELAY_MAX_BYTES: usize = 256 * 1024;
/// What a chat window that would not show says, and all it says.
const CHAT_SHOW_FAILED: &str = "The chat window couldn't be shown.";

/// Whether a relayed message is within the cap, measured as the JSON text it travels as.
fn relay_fits(msg: &serde_json::Value) -> bool {
    serde_json::to_vec(msg).is_ok_and(|bytes| bytes.len() <= RELAY_MAX_BYTES)
}

/// A message between the island's page and the chat window's. The target is checked here; the receiving page checks the message's shape before it acts. Never logged.
#[tauri::command]
fn chat_relay(app: AppHandle, to: String, msg: serde_json::Value) {
    let Some(label) = chat_target(&to) else { return };
    if !relay_fits(&msg) {
        log::line("chat: a message between the windows was too large and was refused");
        return;
    }
    logged_emit("chat-msg", app.emit_to(label, "chat-msg", msg));
}

pub fn run() {
    platform::prepare_environment();
    let (loaded, problem) = settings::load_checked();
    settings::set_save_gate(&problem);
    let gate = Arc::new(PollGate::new());

    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _argv, _cwd| {
            let _ = app.emit_to(island::WINDOW_LABEL, "tray", "open".to_string());
        }))
        .plugin(tauri_plugin_autostart::init(MacosLauncher::LaunchAgent, None))
        .manage(Shared {
            settings: Mutex::new(loaded.clone()),
            settings_problem: Mutex::new(problem),
            gate: gate.clone(),
        })
        .manage(Pending::default())
        .manage(desktop::DesktopGate::new(desktop::Gate::new()))
        .manage(ai::AiState::default())
        .invoke_handler(tauri::generate_handler![
            boot,
            save_settings,
            settings_retry_load,
            settings_start_fresh,
            set_collapsed,
            set_island_rect,
            watch_pointer_buttons,
            focus_window,
            reposition,
            fit_zoom,
            open_url,
            open_in_vscode,
            open_claude_app,
            copy_text,
            quit_app,
            hooks_status,
            hooks_preview,
            hooks_apply,
            agent_hooks_status,
            agent_hooks_preview,
            agent_hooks_apply,
            approval_decision,
            approval_ack,
            approval_decline,
            foreground_app,
            log_line,
            ai::ai_discover,
            ai::ai_list_models,
            ai::ai_resolve,
            ai::ai_prewarm,
            ai::ai_oneshot,
            ai::ai_local_model,
            ai::ai_chat,
            ai::ai_quick,
            ai::ai_cancel,
            ai::ai_load_turns,
            ai::companion_last_sent,
            ai::claude_status,
            ai::claude_set_level,
            ai::claude_pick_folder,
            ai::claude_sign_in,
            chat_reset,
            companion_list,
            companion_load,
            companion_save,
            companion_delete,
            companion_delete_all,
            ingest_file,
            ingest_png,
            drag_out_spike,
            shelf_list,
            shelf_add,
            shelf_remove,
            shelf_clear,
            shelf_ask,
            shelf_drag_out,
            shelf_reveal,
            shelf_send,
            link_cmd::link_state,
            link_cmd::link_set_visible,
            link_cmd::link_set_name,
            link_cmd::link_devices_open,
            link_cmd::link_shelf_open,
            link_cmd::link_pair,
            link_cmd::link_answer_pair,
            link_cmd::link_respond_offer,
            link_cmd::link_cancel_receiving,
            link_cmd::link_dismiss,
            link_cmd::link_forget,
            link_cmd::link_send,
            link_cmd::link_cancel_sending,
            link_cmd::link_reveal_result,
            link_cmd::link_reveal_folder,
            secret_present,
            secret_presence,
            secret_set,
            secret_clear,
            refresh_integration,
            open_n8n,
            open_settings_window,
            show_chat_window,
            hide_chat_window,
            chat_relay,
            set_paused,
            desktop::desktop_screens,
            desktop::desktop_layout,
            desktop::desktop_place,
            desktop::desktop_show,
            desktop::desktop_drag,
            desktop::desktop_native_drag,
            desktop::desktop_awake,
            desktop::desktop_double_click_ms,
            desktop::desktop_cursor,
            desktop::desktop_relay,
            desktop::desktop_menu_text,
            tray::projects_menu_text,
            sidekick::sidekick_idle_seconds,
        ])
        .setup(move |app| {
            let handle = app.handle().clone();
            tray::build(&handle)?;
            // The link between the user's machines (sub-project G2): built here, it listens and announces nothing until the user turns Visible on in Settings -> Devices.
            let link = link_cmd::init(&handle);
            app.manage(link_cmd::LinkHandle(link.clone()));
            link.start();
            // Before the island: see create_settings_window. The desktop cat's window is made the same way, hidden, and its poll thread sleeps until the cat is out.
            create_settings_window(&handle);
            create_chat_window(&handle);
            desktop::create_window(&handle);
            desktop::spawn_poll(handle.clone(), handle.state::<desktop::DesktopGate>().inner().clone());
            // Lock, unlock and display off or on come from the platform's own notifications (nothing polls). Rust combines them (`desktop::AwayState`), parks the desktop poll while away
            // and tells the desktop page, which treats away as hidden.
            let away_handle = handle.clone();
            let away_gate = handle.state::<desktop::DesktopGate>().inner().clone();
            // The Sidekick's page hears the same news (a lock, the display, a sleep) as the words of `presenceStep`; the watcher takes one callback, so this one calls both.
            platform::watch_away(move |source, on| {
                desktop::away_changed(&away_handle, &away_gate, source, on);
                sidekick::away_changed(&away_handle, source, on);
            });

            if let Some(win) = island::window(&handle) {
                platform::make_non_activating(&win);
                island::apply_geometry(&handle, &loaded.screen, false);
                let _ = win.show();
            }
            gate.collapsed.store(false, Ordering::Relaxed);
            // Nothing drawn yet, so nothing takes the mouse until the page
            // reports the island's shape.
            if !platform::CURSOR_POLL {
                island::refresh_click_through(&handle, &gate);
            }
            gate.set_active(true);
            // Under X11 the pointer can be read anywhere on screen; the poll's period and boot's `cursorPoll` follow (platform::pointer_feed).
            platform::detect_pointer_feed();
            island::spawn_cursor_poll(handle.clone(), gate.clone());

            log::line(format!("--- NotchMeow {} started ---", env!("CARGO_PKG_VERSION")));
            hooks::ensure_hook_exe(&handle);
            pipe::start(handle.clone());
            integrations::start(handle.clone());
            // Spec §2: local servers are looked for at launch, then only on demand.
            ai::discover_at_launch(handle.clone());
            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("error while building NotchMeow")
        .run(|_app, event| {
            // Every way out of the app (tray Quit, the Quit command) ends in `Exit`. A `claude` still running would outlive
            // the app: end it and what it started (bounded, about a second).
            if matches!(event, tauri::RunEvent::Exit) {
                ai::claude_run::stop_all();
                // A receive in progress would leave a truncated file in Downloads/NotchMeow: a clean quit removes it.
                link::files::remove_partials();
            }
        });
}

#[cfg(test)]
mod settings_place_tests {
    use super::settings_place;

    fn kept(p: &str) -> Option<String> {
        settings_place(Some(p.to_string()))
    }

    #[test]
    fn keeps_a_page_or_a_page_and_tab() {
        assert_eq!(kept("devices").as_deref(), Some("devices"));
        assert_eq!(kept("chat/keys").as_deref(), Some("chat/keys"));
        assert_eq!(kept("cat/agentcats").as_deref(), Some("cat/agentcats"));
    }

    #[test]
    fn keeps_exactly_32_bytes_and_drops_33() {
        let edge = "a".repeat(32);
        assert_eq!(settings_place(Some(edge.clone())), Some(edge));
        assert_eq!(settings_place(Some("a".repeat(33))), None);
    }

    #[test]
    fn drops_anything_else() {
        for bad in ["Chat", "", "chat/", "/keys", "chat/keys/x", "../x", "chat keys"] {
            assert_eq!(kept(bad), None, "{bad:?} must be dropped");
        }
        // Multi-byte text is dropped by the byte test, not by a character count: a regression to chars() would keep some of these.
        let sixteen_two_byte = "\u{e9}".repeat(16);
        assert_eq!(sixteen_two_byte.len(), 32, "the edge is 32 bytes of non-ASCII");
        for bad in [
            "\u{e9}", "ch\u{e4}t", "\u{ff41}\u{ff42}", "a\u{e9}b/c", sixteen_two_byte.as_str(),
            "a\nb", "a\0", "chat/keys2",
        ] {
            assert_eq!(kept(bad), None, "{bad:?} must be dropped");
        }
        assert_eq!(settings_place(None), None);
    }
}

#[cfg(test)]
mod emit_tests {
    use super::emit_failure_line;

    /// The log line for a failed emit names the event and carries nothing else.
    #[test]
    fn a_failed_emit_is_logged_by_event_name_only() {
        assert_eq!(emit_failure_line("settings-hidden"), "could not send the settings-hidden event");
        assert_eq!(emit_failure_line("settings-changed"), "could not send the settings-changed event");
    }
}

#[cfg(test)]
mod chat_window_tests {
    use super::{chat_open_id, chat_target, relay_fits, url_ok, CHAT_LABEL, RELAY_MAX_BYTES};

    #[test]
    fn the_relay_goes_to_the_island_or_the_chat_window_and_nowhere_else() {
        assert_eq!(chat_target("island"), Some(crate::island::WINDOW_LABEL));
        assert_eq!(chat_target("chat"), Some(CHAT_LABEL));
        for bad in ["", "settings", "desktop", "Chat", "chat ", "island\0", "*", "main"] {
            assert_eq!(chat_target(bad), None, "{bad:?} must not be a target");
        }
    }

    #[test]
    fn a_shown_conversation_id_is_kept_only_when_it_is_the_contracts() {
        assert_eq!(chat_open_id(Some("0a1b2c3d-1111-4222-8333-444455556666".into())).as_deref(), Some("0a1b2c3d-1111-4222-8333-444455556666"));
        assert_eq!(chat_open_id(Some("a".into())).as_deref(), Some("a"));
        assert_eq!(chat_open_id(None), None);
        for bad in ["", "../x", "A", "-a", "a b", "a/b", "a\\b", "a\0", "\u{e9}", &"a".repeat(65)] {
            assert_eq!(chat_open_id(Some(bad.to_string())), None, "{bad:?} must be dropped");
        }
    }

    #[test]
    fn a_relayed_message_is_refused_only_past_256_kib_of_json() {
        // `{"s":""}` is 8 bytes; a string of the rest makes a message of exactly the cap, and one more byte is over it.
        let at_cap = serde_json::json!({ "s": "x".repeat(RELAY_MAX_BYTES - 8) });
        assert_eq!(serde_json::to_vec(&at_cap).unwrap().len(), RELAY_MAX_BYTES);
        assert!(relay_fits(&at_cap));
        let over = serde_json::json!({ "s": "x".repeat(RELAY_MAX_BYTES - 7) });
        assert!(!relay_fits(&over));
        assert!(relay_fits(&serde_json::json!({ "kind": "current", "id": null })));
    }

    #[test]
    fn open_url_keeps_a_plain_web_address() {
        for ok in ["http://a.b", "https://example.com/path?q=1&r=2#frag", "https://a.b/%20x", &format!("https://a.b/{}", "x".repeat(2048 - 12))] {
            assert!(url_ok(ok), "{ok:?} must be kept");
        }
    }

    #[test]
    fn open_url_refuses_other_schemes_and_the_wrong_case() {
        for bad in ["", "http://", "https://", "ftp://a.b", "file:///C:/x", "javascript:alert(1)", "HTTPS://a.b", "Http://a.b", " https://a.b", "https:/a.b", "//a.b"] {
            assert!(!url_ok(bad), "{bad:?} must be refused");
        }
    }

    #[test]
    fn open_url_refuses_whitespace_controls_and_the_characters_a_command_line_would_read() {
        for bad in [
            "https://a.b/x y", "https://a.b/x\ty", "https://a.b/x\ny", "https://a.b/x\ru", "https://a.b/\u{a0}", "https://a.b/\u{2028}", "https://a.b/\u{3000}", "https://a.b/\u{feff}",
            "https://a.b/\u{0}", "https://a.b/\u{1f}", "https://a.b/\u{7f}", "https://a.b/\u{80}", "https://a.b/\u{9f}",
            "https://a.b/\"", "https://a.b/<", "https://a.b/>", "https://a.b/\\", "https://a.b/`", "https://a.b/^", "https://a.b/|", "https://a.b/{", "https://a.b/}",
            "https://a.b/&calc.exe\"", "https://a.b/x\" --x",
        ] {
            assert!(!url_ok(bad), "{bad:?} must be refused");
        }
    }

    #[test]
    fn open_url_refuses_an_address_over_2048_utf16_units_the_way_the_page_counts() {
        let at_limit = format!("https://a.b/{}", "x".repeat(2048 - 12));
        assert_eq!(at_limit.chars().count(), 2048);
        assert!(url_ok(&at_limit));
        assert!(!url_ok(&format!("{at_limit}x")));
        // Two bytes a character (UTF-8) but one UTF-16 unit each: within the limit at 2048 characters, as the page's `url.length` counts.
        let wide = format!("https://a.b/{}", "\u{e9}".repeat(2048 - 12));
        assert!(url_ok(&wide));
        assert!(!url_ok(&format!("{wide}\u{e9}")));
        // An emoji is one code point but two UTF-16 units: 1,036 of them are 1,048 characters and 2,072 units, over the limit.
        let astral = format!("https://a.b/{}", "\u{1f600}".repeat(1036));
        assert!(astral.chars().count() < 2048 && astral.encode_utf16().count() > 2048);
        assert!(!url_ok(&astral));
        let astral_ok = format!("https://a.b/{}", "\u{1f600}".repeat(1018));
        assert_eq!(astral_ok.encode_utf16().count(), 2048);
        assert!(url_ok(&astral_ok));
    }
}
