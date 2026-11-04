// NotchMeow's AI layer: providers, routing, streaming, files, and the commands
// the island and the settings window call. Spec:
// docs/superpowers/specs/2026-10-03-local-models-design.md.
//
// All model traffic goes through Rust (reqwest): no webview Origin reaches a
// local server, and API keys never cross into the webview.

pub mod anthropic;
pub mod attachments;
pub mod budget;
pub mod catalog;
pub mod claude_chat;
pub mod claude_cli;
pub mod claude_code;
pub mod claude_run;
pub mod discovery;
pub mod errors;
pub mod oneshot;
pub mod openai;
pub mod openai_compat;
pub mod provider;
pub mod router;
pub mod session;
pub mod sse;

#[cfg(test)]
pub mod testkit;

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use tauri::ipc::Channel;
use tauri::{AppHandle, Emitter, Manager, State};
use tokio::sync::Notify;

use crate::settings::AiSettings;
use crate::Shared;
use claude_chat::ClaudeChat;
use claude_code::Level;
use discovery::{Probe, Server, ServerStatus};
use errors::Who;
use provider::{Endpoint, ErrorKind, ModelInfo, Placement, Timeouts};
use session::{AiEvent, Conversation, Env, Feature, FileRef, LoadTurn, Resolution, TurnRequest};

/// The AI state the app manages: one conversation, the running turn's Stop
/// switch, the last discovery, the model lists fetched so far and which providers
/// have a key.
#[derive(Default)]
pub struct AiState {
    pub conversation: Mutex<Conversation>,
    cancel: Mutex<Option<Arc<Notify>>>,
    servers: Mutex<Vec<Server>>,
    models: Mutex<HashMap<String, Vec<ModelInfo>>>,
    /// Which providers have a key, read from the keychain once and kept until a key is saved
    /// or removed: the chat and the settings window ask on every focus, and a keychain read
    /// is a blocking OS call. Only presence is kept here, never a key.
    key_presence: Mutex<Option<HashSet<String>>>,
    /// The added server's key (or that there is none), read once and kept until Settings closes
    /// or a key changes, so a rescan or a focus never asks the OS keychain again (Linux keyrings
    /// prompt on every read). It stays in this process, like the keys a turn reads.
    custom_key: Mutex<Option<Option<String>>>,
    /// Bumped whenever a key changes: a read that started before the change is not kept.
    key_epoch: AtomicU64,
    /// The chat's Claude Code session, its level and what the last check found of it.
    pub claude: Arc<Mutex<ClaudeChat>>,
    /// What the companion last sent to a model, one line per message part (memory only). Shared with each turn's `Env`.
    pub sent: Arc<Mutex<Vec<String>>>,
}

impl AiState {
    /// `chat_reset`: a new conversation; a reply still on its way is stopped and dropped.
    pub fn reset(&self) {
        self.conversation.lock().unwrap().reset();
        // A new chat: a new Claude Code session at Chat only. The old id is retired with it.
        self.claude.lock().unwrap().reset();
        self.cancel_running();
    }

    /// A key was saved or removed: the next `ai_resolve` reads the keychain again.
    pub fn forget_key_presence(&self) {
        self.key_epoch.fetch_add(1, Ordering::SeqCst);
        *self.key_presence.lock().unwrap() = None;
        *self.custom_key.lock().unwrap() = None;
    }

    /// The Settings window was closed: its next open reads the added server's key again.
    pub fn forget_custom_key(&self) {
        *self.custom_key.lock().unwrap() = None;
    }

    fn cached_presence(&self) -> Option<HashSet<String>> {
        self.key_presence.lock().unwrap().clone()
    }

    /// Keeps a read that began at `epoch`, unless a key changed since.
    fn remember_presence(&self, epoch: u64, present: HashSet<String>) {
        let mut slot = self.key_presence.lock().unwrap();
        if self.key_epoch.load(Ordering::SeqCst) == epoch {
            *slot = Some(present);
        }
    }

    /// Writes discovery results by server id: each probed server takes `fresh`'s row, or keeps the row it
    /// already has when `fresh` has none, so a late phase can't overwrite a newer result of the other.
    /// Rows of servers no longer probed (the user removed or changed the added one) are dropped; order
    /// follows `probes`.
    fn merge(&self, probes: &[Probe], fresh: Vec<Server>) {
        let mut servers = self.servers.lock().unwrap();
        let merged = probes
            .iter()
            .filter_map(|p| {
                let same = |s: &&Server| s.provider == p.provider && s.base_url == p.base_url;
                fresh.iter().find(same).or_else(|| servers.iter().find(same)).cloned()
            })
            .collect();
        *servers = merged;
    }

    fn cancel_running(&self) {
        if let Some(c) = self.cancel.lock().unwrap().as_ref() {
            c.notify_one();
        }
    }

    /// One turn at a time: `None` while a reply is still streaming.
    fn begin_turn(&self) -> Option<Running<'_>> {
        let mut slot = self.cancel.lock().unwrap();
        if slot.is_some() {
            return None;
        }
        let cancel = Arc::new(Notify::new());
        *slot = Some(cancel.clone());
        Some(Running { state: self, cancel })
    }
}

/// The running turn's Stop switch; cleared however the turn ends.
struct Running<'a> {
    state: &'a AiState,
    cancel: Arc<Notify>,
}

impl Drop for Running<'_> {
    fn drop(&mut self) {
        *self.state.cancel.lock().unwrap() = None;
    }
}

/// Keys from the OS keychain, by provider id. They stay on this side. A blocking
/// call: only a turn needs the values, and it reads them off the async threads.
/// `catalog::keychain_name` gives the item: the added server's is `custom-server-key.default`.
fn read_keys() -> HashMap<String, Option<String>> {
    catalog::PROVIDERS
        .iter()
        .filter_map(|p| Some((p.id.to_string(), Some(crate::secrets::get(&catalog::keychain_name(p.id)?)?))))
        .collect()
}

/// Which providers have a key: the ids `read_keys` would return, without the values.
fn read_presence() -> HashSet<String> {
    catalog::PROVIDERS
        .iter()
        .filter_map(|p| crate::secrets::present(&catalog::keychain_name(p.id)?).then(|| p.id.to_string()))
        .collect()
}

/// Which providers have a key, from the cache or, once, from `read` (the keychain). `read`
/// is a blocking OS call, so it runs off the async threads.
async fn present_providers(ai: &AiState, read: impl FnOnce() -> HashSet<String> + Send + 'static) -> HashSet<String> {
    if let Some(known) = ai.cached_presence() {
        return known;
    }
    let epoch = ai.key_epoch.load(Ordering::SeqCst);
    let found = tokio::task::spawn_blocking(read).await.unwrap_or_default();
    ai.remember_presence(epoch, found.clone());
    found
}

/// The added server's key, from the cache or, once, from `read` (the keychain, a blocking OS
/// call that runs off the async threads).
async fn custom_key(ai: &AiState, read: impl FnOnce() -> Option<String> + Send + 'static) -> Option<String> {
    if let Some(known) = ai.custom_key.lock().unwrap().clone() {
        return known;
    }
    let epoch = ai.key_epoch.load(Ordering::SeqCst);
    let found = tokio::task::spawn_blocking(read).await.ok().flatten();
    let mut slot = ai.custom_key.lock().unwrap();
    if ai.key_epoch.load(Ordering::SeqCst) == epoch {
        *slot = Some(found.clone());
    }
    found
}

fn probes(settings: &AiSettings, custom_key: Option<String>) -> Vec<Probe> {
    let mut probes = discovery::localhost_probes();
    if let Some(url) = &settings.custom_server {
        probes.extend(discovery::custom_probe(url, custom_key));
    }
    probes
}

/// The `Env` for a turn: the keys themselves, read once for this turn.
async fn turn_env(shared: &Shared, ai: &AiState) -> Env {
    let settings = shared.settings.lock().unwrap().ai.clone();
    let keys = tokio::task::spawn_blocking(read_keys).await.unwrap_or_default();
    Env {
        probes: probes(&settings, keys.get("custom").cloned().flatten()),
        settings,
        keys,
        servers: ai.servers.lock().unwrap().clone(),
        cloud_override: catalog::debug_override(),
        claude: ai.claude.clone(),
        models: ai.models.lock().unwrap().clone(),
        timeouts: None,
        system: None,
        sent: ai.sent.clone(),
    }
}

/// The `Env` for what the user sees (the model chip, the settings line, the drop card,
/// pre-warming): which providers have a key, never the keys. Their values are `None`: a turn
/// built from this `Env` finds no key to send, and nothing built from it makes a cloud request.
async fn display_env(shared: &Shared, ai: &AiState) -> Env {
    let settings = shared.settings.lock().unwrap().ai.clone();
    let keys = present_providers(ai, read_presence).await.into_iter().map(|p| (p, None)).collect();
    Env {
        probes: Vec::new(),
        settings,
        keys,
        servers: ai.servers.lock().unwrap().clone(),
        cloud_override: catalog::debug_override(),
        claude: ai.claude.clone(),
        models: ai.models.lock().unwrap().clone(),
        timeouts: None,
        system: None,
        sent: Arc::new(Mutex::new(Vec::new())),
    }
}

/// Writes back what a turn learned — the last-used local model, nothing else, so
/// a choice made in the picker while the reply streamed is kept — and tells both
/// windows through the existing `settings-changed` event.
fn store_learned(app: &AppHandle, shared: &Shared, learned: &AiSettings) {
    // Written first: the shared copy and the windows hear of the value only once settings.json holds it.
    let change = |s: &mut crate::settings::Settings| {
        if s.ai.last_used_local == learned.last_used_local && s.ai.local_models == learned.local_models {
            return false;
        }
        s.ai.last_used_local = learned.last_used_local.clone();
        s.ai.local_models = learned.local_models.clone();
        true
    };
    match crate::settings::update(&shared.settings, change, crate::settings::save) {
        Ok(Some(updated)) => crate::logged_emit("settings-changed", app.emit("settings-changed", updated)),
        Ok(None) => {}
        Err(_) => crate::log::line("settings.json could not be saved"),
    }
}

/// Only files NotchMeow copied into its own inbox may be read for the chat.
/// The check uses canonical paths, but the path kept is the one given: on
/// Windows a canonical path starts with `\\?\`, which WinRT's OCR refuses.
fn inbox_file(path: &str, inbox: &Path) -> Option<FileRef> {
    let inbox = std::fs::canonicalize(inbox).ok()?;
    let real = std::fs::canonicalize(path).ok()?;
    if !real.starts_with(&inbox) || !real.is_file() {
        return None;
    }
    let name = Path::new(path).file_name()?.to_string_lossy().to_string();
    Some(FileRef { name, path: PathBuf::from(path) })
}

/// One scan: the localhost results are stored and returned as soon as that phase ends, with the added
/// server as the last scan left it. The added server's check finishes in the background and hands its
/// rows to `on_added` (only when there is such a server).
async fn scan(ai: &AiState, probes: Vec<Probe>, on_added: impl FnOnce(Vec<Server>) + Send + 'static) -> Vec<Server> {
    let (local, added) = discovery::discover_split(
        probes.clone(),
        Duration::from_millis(catalog::PROBE_MS),
        Duration::from_millis(catalog::ADDED_PROBE_MS),
    )
    .await;
    ai.merge(&probes, local);
    tokio::spawn(async move {
        if let Ok(rows) = added.await {
            if !rows.is_empty() {
                on_added(rows);
            }
        }
    });
    ai.servers.lock().unwrap().clone()
}

/// Checks localhost (and the server the user added) for model servers. Returns when localhost has
/// answered; if the added server is slow it joins afterwards, and `ai-servers-changed` carries the
/// full list for the picker and Settings to redraw.
#[tauri::command]
pub async fn ai_discover(app: AppHandle, shared: State<'_, Shared>, ai: State<'_, AiState>) -> Result<Vec<Server>, String> {
    let settings = shared.settings.lock().unwrap().ai.clone();
    // Only the added server's key is needed, and only when there is such a server.
    let custom_key = match settings.custom_server {
        Some(_) => custom_key(&ai, || catalog::keychain_name("custom").and_then(|key| crate::secrets::get(&key))).await,
        None => None,
    };
    let probes = probes(&settings, custom_key);
    let later = {
        let (app, probes) = (app.clone(), probes.clone());
        move |added: Vec<Server>| {
            let ai = app.state::<AiState>();
            ai.merge(&probes, added);
            crate::logged_emit("ai-servers-changed", app.emit("ai-servers-changed", ai.servers.lock().unwrap().clone()));
        }
    };
    Ok(scan(&ai, probes, later).await)
}

/// A cloud provider's model list with this key. It doubles as the key check behind the
/// settings window's ✓ / ✗: `Err` carries the words shown after the ✗ ("Your OpenAI key was
/// rejected."). `root` is the debug-only redirect to the fake server.
async fn cloud_models(provider: &str, key: String, root: Option<&str>) -> Result<Vec<ModelInfo>, String> {
    let def = catalog::get(provider).filter(|d| catalog::is_cloud(d.id)).ok_or("unknown provider")?;
    let who = Who { provider: provider.to_string(), name: def.name.to_string() };
    let endpoint = Endpoint {
        provider: provider.to_string(),
        name: def.name.to_string(),
        base_url: catalog::base_url(provider, root).unwrap_or_default(),
        key: Some(key),
        placement: Placement::Cloud,
        timeouts: Timeouts::for_placement(Placement::Cloud),
    };
    session::make_provider(endpoint).list_models().await.map_err(|e| {
        // Google answers a bad key with HTTP 400 "API key not valid"; the contract's `bad_request` stays
        // for chat, but for this key check a 400 is a rejected key.
        let kind = if e.status == Some(400) { ErrorKind::Auth } else { e.kind };
        errors::error_copy(kind, &who, Some(&e)).text
    })
}

/// A provider's live model list. For a cloud provider it doubles as the key check behind the
/// settings window's ✓ / ✗.
#[tauri::command]
pub async fn ai_list_models(ai: State<'_, AiState>, provider: String) -> Result<Vec<ModelInfo>, String> {
    if !catalog::is_cloud(&provider) {
        let servers = ai.servers.lock().unwrap().clone();
        return Ok(servers
            .into_iter()
            .find(|s| s.provider == provider && s.status == ServerStatus::Running)
            .map(|s| s.models)
            .unwrap_or_default());
    }
    let id = provider.clone();
    let key = tokio::task::spawn_blocking(move || catalog::keychain_name(&id).and_then(|key| crate::secrets::get(&key)))
        .await
        .ok()
        .flatten()
        .ok_or_else(|| "No key yet.".to_string())?;
    let list = cloud_models(&provider, key, catalog::debug_override().as_deref()).await?;
    ai.models.lock().unwrap().insert(provider, list.clone());
    Ok(list)
}

/// What a feature resolves to now: the model chip, the settings line, the drop card.
/// Async, so the keychain is never read on the main thread, and the answer comes from the
/// cached key presence, so focusing the chat doesn't read it again.
#[tauri::command]
pub async fn ai_resolve(shared: State<'_, Shared>, ai: State<'_, AiState>, feature: Feature) -> Result<Resolution, String> {
    Ok(session::resolve(&display_env(&shared, &ai).await, feature))
}

/// Opening the chat loads the selected local model ahead of the first message.
#[tauri::command]
pub async fn ai_prewarm(shared: State<'_, Shared>, ai: State<'_, AiState>, feature: Feature) -> Result<(), String> {
    let env = display_env(&shared, &ai).await;
    let res = session::resolve(&env, feature);
    let (Some(provider), Some(model)) = (res.provider, res.model) else { return Ok(()) };
    let Some(server) = env.servers.iter().find(|s| s.provider == provider && s.status == ServerStatus::Running) else {
        return Ok(());
    };
    let endpoint = Endpoint {
        provider,
        name: server.name.clone(),
        base_url: server.base_url.clone(),
        key: None,
        placement: server.placement,
        timeouts: Timeouts::for_placement(server.placement),
    };
    tauri::async_runtime::spawn(async move {
        session::make_provider(endpoint).prewarm(&model).await;
    });
    Ok(())
}

/// The server and the model a one-shot may ask (sub-project F1, "The local voice"): a model on this computer, looked for again now (a server started after the app was: a 0.3 s look at
/// the local addresses only), chosen by the router's local rule and never by the chat's own choice. None when there is none. No key is read and nothing is logged.
async fn local_target(shared: &Shared, ai: &AiState) -> Option<(Endpoint, String)> {
    let mut env = display_env(shared, ai).await;
    env.probes = probes(&env.settings, None);
    env.rediscover(None).await;
    let ready = session::ready_list(&env);
    let pick = oneshot::pick(&ready, env.settings.last_used_local.as_ref())?;
    let server = env.servers.iter().find(|s| s.provider == pick.provider && s.status == ServerStatus::Running && s.placement == Placement::Local)?;
    let endpoint = Endpoint {
        provider: pick.provider.clone(),
        name: server.name.clone(),
        base_url: server.base_url.clone(),
        key: None,
        placement: server.placement,
        timeouts: Timeouts::for_placement(server.placement),
    };
    Some((endpoint, pick.model))
}

/// The Sidekick's local voice: one short question to a model on this computer (never a network or cloud model, never the chat's Auto choice), and its answer as one line, or null. It
/// is one request, not a conversation: nothing is stored, the chat's history is untouched, and nothing is logged. It gives up after `oneshot::TIMEOUT_SECS` seconds, on any error and
/// when there is no local model: the page then keeps the plain template. The page decides what it may be given (only the facts of a note); this refuses a request over 1200 characters.
#[tauri::command]
pub async fn ai_oneshot(shared: State<'_, Shared>, ai: State<'_, AiState>, system: String, prompt: String) -> Result<Option<String>, String> {
    if !oneshot::within_limits(&system, &prompt) {
        return Ok(None);
    }
    let Some((endpoint, model)) = local_target(&shared, &ai).await else { return Ok(None) };
    let provider = session::make_provider(endpoint);
    let request = oneshot::request(&model, &system, &prompt);
    let mut sink = |_: provider::ChatChunk| {};
    let asked = tokio::time::timeout(Duration::from_secs(oneshot::TIMEOUT_SECS), provider.stream(&request, &mut sink)).await;
    Ok(match asked {
        Ok(Ok(done)) if done.error.is_none() && done.refusal.is_none() => oneshot::clean_reply(&done.text),
        _ => None,
    })
}

/// The name of the local model the Sidekick's wording would come from ("qwen3.5:2b"), or null when there is none: the "Found" line of Settings → Sidekick.
#[tauri::command]
pub async fn ai_local_model(shared: State<'_, Shared>, ai: State<'_, AiState>) -> Result<Option<String>, String> {
    Ok(local_target(&shared, &ai).await.map(|(_, model)| model))
}

/// A chat turn's gate. A quick Explain arms the chat's hold first, before anything can refuse the turn, so the page's "No tools"
/// and Rust agree; the Claude lock is taken for a quick turn only. Then the one-reply gate is taken.
fn start_chat_turn(ai: &AiState, quick: bool) -> Option<Running<'_>> {
    if quick {
        ai.claude.lock().unwrap().quick_hold = true;
    }
    ai.begin_turn()
}

/// One chat turn, streamed to the island over `on_event`.
#[tauri::command]
#[allow(clippy::too_many_arguments)]
pub async fn ai_chat(
    app: AppHandle,
    shared: State<'_, Shared>,
    ai: State<'_, AiState>,
    feature: Feature,
    text: String,
    attachments: Vec<String>,
    regenerate: bool,
    system: Option<String>,
    // Required: a caller that forgets it would otherwise get a normal turn, with tools, from a quick Explain.
    quick: bool,
    on_event: Channel<AiEvent>,
) -> Result<(), String> {
    // Armed before the gate and the inbox check below, which can both refuse the turn.
    let running = start_chat_turn(&ai, quick).ok_or_else(|| "A reply is still on its way.".to_string())?;
    // Before a chat's first turn: is Claude Code there, and signed in? (Never on a timer.)
    let wants_claude = {
        let settings = shared.settings.lock().unwrap().ai.clone();
        let by_choice = matches!(settings.choice(feature), router::Choice::Explicit(m) if m.provider == "claudeCode");
        ai.conversation.lock().unwrap().turns.is_empty() && (settings.claude_code_enabled || by_choice)
    };
    if wants_claude {
        let env = claude_cli::current_environment();
        if let Ok(found) = tokio::task::spawn_blocking(move || claude_cli::status(&env)).await {
            ai.claude.lock().unwrap().status = found;
        }
    }
    let inbox = crate::files::inbox_dir();
    let mut files = Vec::new();
    for path in &attachments {
        files.push(inbox_file(path, &inbox).ok_or_else(|| "That file is no longer in NotchMeow's inbox.".to_string())?);
    }
    let mut env = turn_env(&shared, &ai).await;
    // The companion's text for this turn; an empty one keeps the built-in prompt.
    env.system = system.filter(|s| !s.is_empty());
    let mut emit = |event: AiEvent| {
        let _ = on_event.send(event);
    };
    let request = TurnRequest { feature, text, files, regenerate, quick };
    session::run_turn(&mut env, &ai.conversation, request, &running.cancel, &mut emit).await;
    *ai.servers.lock().unwrap() = env.servers;
    ai.models.lock().unwrap().extend(env.models);
    store_learned(&app, &shared, &env.settings);
    Ok(())
}

/// A quick action (Fix or Rewrite), streamed over `on_event` like a chat turn but with its own history: the chat's conversation,
/// its Claude session and "What the AI saw last" are never touched (`session::quick_env`). Explain and Explain this screenshot are normal chat turns (`ai_chat`). It takes the same one-reply gate and the same inbox check as `ai_chat`.
#[tauri::command]
#[allow(clippy::too_many_arguments)]
pub async fn ai_quick(
    app: AppHandle,
    shared: State<'_, Shared>,
    ai: State<'_, AiState>,
    feature: Feature,
    system: String,
    text: String,
    attachments: Vec<String>,
    on_event: Channel<AiEvent>,
) -> Result<(), String> {
    let running = ai.begin_turn().ok_or_else(|| "A reply is still on its way.".to_string())?;
    let inbox = crate::files::inbox_dir();
    let mut files = Vec::new();
    for path in &attachments {
        files.push(inbox_file(path, &inbox).ok_or_else(|| "That file is no longer in NotchMeow's inbox.".to_string())?);
    }
    let status = ai.claude.lock().unwrap().status.clone();
    let mut env = session::quick_env(turn_env(&shared, &ai).await, &system, status);
    let mut emit = |event: AiEvent| {
        let _ = on_event.send(event);
    };
    let request = TurnRequest { feature, text, files, regenerate: false, quick: false };
    let quick_history = Mutex::new(Conversation::default());
    session::run_turn(&mut env, &quick_history, request, &running.cancel, &mut emit).await;
    *ai.servers.lock().unwrap() = env.servers;
    ai.models.lock().unwrap().extend(env.models);
    store_learned(&app, &shared, &env.settings);
    Ok(())
}

/// A saved conversation is opened: the chat starts afresh with its words as the history. A session that is told them carries a recap
/// on its first turn (`Session::reseed`).
#[tauri::command]
pub fn ai_load_turns(ai: State<'_, AiState>, turns: Vec<LoadTurn>) {
    ai.reset();
    let loaded = session::loaded_turns(&turns);
    let any = !loaded.is_empty();
    ai.conversation.lock().unwrap().turns = loaded;
    if any {
        ai.claude.lock().unwrap().session.reseed();
    }
}

/// What the companion last sent to a model, one line per message part (memory only, never a file).
#[tauri::command]
pub fn companion_last_sent(ai: State<'_, AiState>) -> Vec<String> {
    ai.sent.lock().unwrap().clone()
}

/// Empties what the companion last sent: after Delete all, What the AI saw last shows nothing (the Mac's clearSent).
pub fn forget_sent(sent: &Mutex<Vec<String>>) {
    sent.lock().unwrap().clear();
}

/// Stop: cancels the stream on its way.
#[tauri::command]
pub fn ai_cancel(ai: State<'_, AiState>) {
    ai.cancel_running();
}

/// Claude Code: where it is, its version and whether it is signed in. Looked at when Settings opens and before a chat's
/// first turn, never on a timer. Blocking work, off the async threads.
#[tauri::command]
pub async fn claude_status(ai: State<'_, AiState>) -> Result<claude_cli::Status, String> {
    let env = claude_cli::current_environment();
    let found = tokio::task::spawn_blocking(move || claude_cli::status(&env)).await.map_err(|e| e.to_string())?;
    ai.claude.lock().unwrap().status = found.clone();
    Ok(found)
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LevelDto {
    pub level: &'static str,
    pub folder: Option<String>,
}

/// The level a picker pick names. `none` is not a pick: only the quick actions run at it, so it is refused like any unknown level.
fn chosen_level(level: &str, folder: Option<String>) -> Result<Level, String> {
    match (level, folder) {
        ("chat", _) => Ok(Level::ChatOnly),
        ("read", Some(f)) => Ok(Level::ReadOnly(claude_cli::check_folder(&f)?)),
        ("agent", Some(f)) => Ok(Level::Agent(claude_cli::check_folder(&f)?)),
        _ => Err("Pick a folder first.".to_string()),
    }
}

/// What Claude may do in this chat: `chat`, or `read` / `agent` with a folder that exists. A new chat starts at `chat`.
#[tauri::command]
pub fn claude_set_level(ai: State<'_, AiState>, level: String, folder: Option<String>) -> Result<LevelDto, String> {
    let chosen = chosen_level(&level, folder)?;
    let dto = LevelDto { level: chosen.key(), folder: chosen.folder().map(str::to_string) };
    // Any pick ends the quick hold; it applies from the next turn.
    ai.claude.lock().unwrap().set_level(chosen);
    Ok(dto)
}

/// The system's folder dialog; `None` when cancelled or when this system has none (the chat then asks for the path as text).
#[tauri::command]
pub async fn claude_pick_folder() -> Option<String> {
    tokio::task::spawn_blocking(claude_cli::pick_folder).await.ok().flatten()
}

/// "Sign in": a terminal runs `claude auth login`, which finishes in the browser. NotchMeow never sees the login.
#[tauri::command]
pub async fn claude_sign_in(ai: State<'_, AiState>) -> Result<bool, String> {
    let exe = ai.claude.lock().unwrap().status.executable.clone();
    let Some(exe) = exe else { return Ok(false) };
    Ok(tokio::task::spawn_blocking(move || claude_cli::open_sign_in(&exe)).await.unwrap_or(false))
}

/// Discovery at launch (spec §2), in the background.
pub fn discover_at_launch(app: AppHandle) {
    tauri::async_runtime::spawn(async move {
        let shared = app.state::<Shared>();
        let ai = app.state::<AiState>();
        let _ = ai_discover(app.clone(), shared, ai).await;
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn forget_sent_empties_what_the_companion_last_sent() {
        let sent = Mutex::new(vec!["[user] a sample question".to_string()]);
        forget_sent(&sent);
        assert!(sent.lock().unwrap().is_empty(), "Delete all leaves What the AI saw last empty");
    }

    #[test]
    fn none_is_never_a_pick() {
        assert_eq!(chosen_level("none", None), Err("Pick a folder first.".to_string()), "the picker never sets no tools");
        assert_eq!(chosen_level("none", Some("/x".into())), Err("Pick a folder first.".to_string()));
        assert_eq!(chosen_level("chat", None), Ok(Level::ChatOnly));
    }

    #[test]
    fn a_new_chat_and_an_opened_conversation_end_the_quick_hold() {
        let ai = AiState::default();
        {
            let mut chat = ai.claude.lock().unwrap();
            chat.quick_hold = true;
            chat.level = Level::ReadOnly("/x".into());
        }
        ai.reset();
        let chat = ai.claude.lock().unwrap();
        assert!(!chat.quick_hold, "a new chat or an opened conversation ends the hold");
        assert_eq!(chat.level, Level::ChatOnly);
    }

    #[test]
    fn a_quick_request_arms_the_hold_before_any_refusal() {
        let ai = AiState::default();
        let busy = ai.begin_turn().expect("idle state starts a turn");
        assert!(start_chat_turn(&ai, true).is_none(), "a reply still on its way refuses the quick Explain");
        assert!(ai.claude.lock().unwrap().quick_hold, "the refused quick Explain still holds the chat at No tools");
        drop(busy);
        let running = start_chat_turn(&ai, true).expect("idle state starts the quick turn");
        drop(running);
        assert!(ai.claude.lock().unwrap().quick_hold, "a later refusal in ai_chat (the inbox check) keeps the hold too");
    }

    #[test]
    fn a_turn_that_is_not_quick_never_arms_the_hold() {
        let ai = AiState::default();
        let busy = ai.begin_turn().expect("idle state starts a turn");
        assert!(start_chat_turn(&ai, false).is_none(), "a refused normal turn is refused");
        assert!(!ai.claude.lock().unwrap().quick_hold, "a refused normal turn leaves the chat's level alone");
        drop(busy);
        assert!(start_chat_turn(&ai, false).is_some(), "idle state starts a normal turn");
        assert!(!ai.claude.lock().unwrap().quick_hold, "a normal turn never holds the chat");
    }

    /// A normal turn does not lock `ai.claude`, so a poisoned lock (a panic while it was held) cannot newly affect it.
    #[test]
    fn a_normal_turn_never_takes_the_claude_lock() {
        let ai = AiState::default();
        let claude = ai.claude.clone();
        assert!(std::thread::spawn(move || {
            let _held = claude.lock().unwrap();
            panic!("poison the lock");
        })
        .join()
        .is_err());
        assert!(ai.claude.is_poisoned());
        assert!(start_chat_turn(&ai, false).is_some(), "a normal turn starts without touching the lock");
    }

    #[test]
    fn one_turn_at_a_time() {
        let ai = AiState::default();
        let first = ai.begin_turn().expect("idle state starts a turn");
        assert!(ai.begin_turn().is_none(), "a second send while a reply streams is refused");
        ai.cancel_running();
        drop(first);
        assert!(ai.begin_turn().is_some(), "the switch clears when the turn ends");
    }

    #[tokio::test]
    async fn focusing_reads_the_keychain_once_not_every_time() {
        use std::sync::atomic::AtomicUsize;
        let ai = AiState::default();
        let reads = Arc::new(AtomicUsize::new(0));
        let counting = |reads: &Arc<AtomicUsize>| {
            let reads = reads.clone();
            move || {
                reads.fetch_add(1, Ordering::SeqCst);
                HashSet::from(["openai".to_string()])
            }
        };
        for _ in 0..5 {
            assert_eq!(present_providers(&ai, counting(&reads)).await, HashSet::from(["openai".to_string()]));
        }
        assert_eq!(reads.load(Ordering::SeqCst), 1, "five focuses, one keychain read");
        // A key was saved or removed (`secret_set`, `secret_clear`): the next look reads again.
        ai.forget_key_presence();
        present_providers(&ai, counting(&reads)).await;
        assert_eq!(reads.load(Ordering::SeqCst), 2);
    }

    #[tokio::test]
    async fn rescanning_reads_the_added_servers_key_once_per_settings_open() {
        use std::sync::atomic::AtomicUsize;
        let ai = AiState::default();
        let reads = Arc::new(AtomicUsize::new(0));
        let counting = |reads: &Arc<AtomicUsize>| {
            let reads = reads.clone();
            move || {
                reads.fetch_add(1, Ordering::SeqCst);
                Some("studio-key".to_string())
            }
        };
        for _ in 0..5 {
            assert_eq!(custom_key(&ai, counting(&reads)).await.as_deref(), Some("studio-key"));
        }
        assert_eq!(reads.load(Ordering::SeqCst), 1, "five focuses and rescans, one keychain read");
        // Settings closed: the next open reads again.
        ai.forget_custom_key();
        custom_key(&ai, counting(&reads)).await;
        assert_eq!(reads.load(Ordering::SeqCst), 2);
        // A key saved or removed also forgets it.
        ai.forget_key_presence();
        custom_key(&ai, counting(&reads)).await;
        assert_eq!(reads.load(Ordering::SeqCst), 3);
        // No key stored is an answer too: it is not asked again.
        ai.forget_custom_key();
        let none = Arc::new(AtomicUsize::new(0));
        for _ in 0..3 {
            let none = none.clone();
            assert_eq!(custom_key(&ai, move || { none.fetch_add(1, Ordering::SeqCst); None }).await, None);
        }
        assert_eq!(none.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn a_keychain_read_that_raced_a_key_change_is_not_kept() {
        let ai = AiState::default();
        let started = ai.key_epoch.load(Ordering::SeqCst); // the read begins…
        ai.forget_key_presence(); // …a key is saved meanwhile…
        ai.remember_presence(started, HashSet::new()); // …and the old answer arrives late.
        assert_eq!(ai.cached_presence(), None);
    }

    #[tokio::test]
    async fn the_key_check_lists_models_and_says_why_a_key_failed() {
        // The fake model server answers GET /v1/models, so any key "works" against it.
        let fake = testkit::FakeServer::start(&[]);
        let claude = cloud_models("anthropic", "sk-ant-test".into(), Some(&fake.base)).await.unwrap();
        assert_eq!(claude.len(), 2);
        assert_eq!(fake.requests()[0]["path"], "/v1/models?limit=100");
        // OpenAI keeps chat models only and Google drops embeddings; a list, even an empty one, is a pass.
        assert!(cloud_models("openai", "sk-test".into(), Some(&fake.base)).await.unwrap().is_empty());
        let google = cloud_models("google", "AIza-test".into(), Some(&fake.base)).await.unwrap();
        assert_eq!(google.iter().map(|m| m.id.as_str()).collect::<Vec<_>>(), ["llama3.2"]);

        // What the settings window prints after the ✗.
        let rejected = |body: &str, status: u16| testkit::canned_server(status, "application/json", body);
        let claude_401 = rejected(r#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#, 401);
        assert_eq!(cloud_models("anthropic", "nope".into(), Some(&claude_401)).await.unwrap_err(), "Your Anthropic key was rejected.");
        let openai_401 = rejected(r#"{"error":{"message":"Incorrect API key","type":"invalid_request_error","code":"invalid_api_key"}}"#, 401);
        assert_eq!(cloud_models("openai", "nope".into(), Some(&openai_401)).await.unwrap_err(), "Your OpenAI key was rejected.");
        // Google answers a bad key with HTTP 400 "API key not valid": on this call (and only here) that is a rejected key.
        let google_400 = rejected(r#"{"error":{"code":400,"message":"API key not valid. Please pass a valid API key.","status":"INVALID_ARGUMENT"}}"#, 400);
        assert_eq!(cloud_models("google", "nope".into(), Some(&google_400)).await.unwrap_err(), "Your Google key was rejected.");
        let openai_429 = rejected(r#"{"error":{"type":"insufficient_quota","code":"insufficient_quota","message":"quota"}}"#, 429);
        assert_eq!(cloud_models("openai", "sk-test".into(), Some(&openai_429)).await.unwrap_err(), "Your OpenAI credit ran out.");
        let port = std::net::TcpListener::bind("127.0.0.1:0").unwrap().local_addr().unwrap().port();
        let down = format!("http://127.0.0.1:{port}");
        assert_eq!(cloud_models("openai", "sk-test".into(), Some(&down)).await.unwrap_err(), "Couldn't reach OpenAI. Check your connection.");
        assert_eq!(cloud_models("ollama", "x".into(), None).await.unwrap_err(), "unknown provider");
    }

    #[tokio::test]
    async fn discovery_returns_after_localhost_and_the_added_server_joins_later_without_overwriting() {
        let local = testkit::FakeServer::start(&["--persona", "ollama"]);
        let lan = testkit::FakeServer::start(&["--fail", "slow-models", "--delay", "1"]); // answers after 1 s
        let probes = vec![
            Probe { provider: "ollama".into(), base_url: local.base.clone(), key: None },
            Probe { provider: "custom".into(), base_url: lan.base.clone(), key: None },
        ];
        let ai = Arc::new(AiState::default());
        let (done, joined) = tokio::sync::oneshot::channel();
        let later = {
            let (ai, probes) = (ai.clone(), probes.clone());
            move |far: Vec<Server>| {
                ai.merge(&probes, far);
                let _ = done.send(());
            }
        };
        let started = std::time::Instant::now();
        let first = scan(&ai, probes.clone(), later).await;
        assert!(started.elapsed() < Duration::from_millis(900), "the picker waited for the added server: {:?}", started.elapsed());
        assert_eq!(first.iter().map(|s| (s.provider.as_str(), s.status)).collect::<Vec<_>>(), [("ollama", ServerStatus::Running)]);

        // Meanwhile a newer localhost result lands (a later scan, or a turn that found Ollama down).
        let mut newer = first[0].clone();
        newer.status = ServerStatus::Off;
        ai.merge(&probes, vec![newer]);

        joined.await.unwrap();
        let now = ai.servers.lock().unwrap().clone();
        assert_eq!(
            now.iter().map(|s| (s.provider.as_str(), s.status)).collect::<Vec<_>>(),
            [("ollama", ServerStatus::Off), ("custom", ServerStatus::Running)],
            "the late merge adds its own row and keeps the newer localhost one, in probe order"
        );
    }

    #[test]
    fn a_merge_drops_rows_of_servers_that_are_no_longer_probed() {
        let ai = AiState::default();
        let old = Probe { provider: "custom".into(), base_url: "http://old-pc:1234".into(), key: None };
        let row = |p: &Probe| {
            let (host, placement, unencrypted) = discovery::describe(&p.provider, &p.base_url);
            Server { provider: p.provider.clone(), name: host.clone(), base_url: p.base_url.clone(), host, placement, status: ServerStatus::Running, models: Vec::new(), unencrypted }
        };
        ai.merge(std::slice::from_ref(&old), vec![row(&old)]);
        let new = Probe { provider: "custom".into(), base_url: "http://new-pc:1234".into(), key: None };
        ai.merge(std::slice::from_ref(&new), Vec::new());
        assert!(ai.servers.lock().unwrap().is_empty(), "the removed server's row is gone; the new one is unknown until it answers");
    }

    #[test]
    fn only_inbox_files_are_read_and_their_path_is_kept() {
        let root = testkit::TempDir::new("inbox");
        let inbox = root.path().join("inbox");
        std::fs::create_dir_all(&inbox).unwrap();
        let inside = inbox.join("Zoé notes.txt");
        std::fs::write(&inside, "hi").unwrap();
        let outside = root.path().join("secret.txt");
        std::fs::write(&outside, "no").unwrap();

        let given = inside.to_string_lossy().to_string();
        let got = inbox_file(&given, &inbox).expect("a file in the inbox is accepted");
        assert_eq!(got.path, PathBuf::from(&given), "the path is not rewritten (no \\\\?\\ prefix)");
        assert_eq!(got.name, "Zoé notes.txt");
        assert!(inbox_file(&outside.to_string_lossy(), &inbox).is_none());
        let sneaky = inbox.join("..").join("secret.txt");
        assert!(inbox_file(&sneaky.to_string_lossy(), &inbox).is_none());
        assert!(inbox_file(&inbox.to_string_lossy(), &inbox).is_none(), "a folder is not a file");
    }
}
