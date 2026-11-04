// One conversation, and one turn of it: route, stream, fall back once, keep the
// history provider-neutral so any model can pick it up. Everything the island
// sees arrives as `AiEvent`s. Logs record event types and errors only — never a
// prompt, a file, a file name or a key.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use serde::{Deserialize, Serialize};
use tokio::sync::Notify;

use crate::ai::anthropic::Anthropic;
use crate::ai::attachments::{self, Prepared, PrepareError, Reader};
use crate::ai::budget;
use crate::ai::catalog::{self, Api};
use crate::ai::claude_chat::{self, ClaudeChat};
use crate::ai::claude_cli;
use crate::ai::claude_code::{self, Platform};
use crate::ai::claude_run::{ClaudeCode, Run, Timings as ClaudeTimings};
use crate::ai::discovery::{self, Probe, Server, ServerStatus};
use crate::ai::errors::{self, Action, Who};
use crate::ai::openai::OpenAI;
use crate::ai::openai_compat::OpenAICompat;
use crate::ai::provider::{
    file_label, AiError, Aggregate, ChatChunk, ChatRequest, Endpoint, EngineReport, ErrorKind, Finish, Message, ModelInfo,
    ModelProvider, Part, Placement, Role, Step, Timeouts,
};
use crate::ai::router::{self, Choice, ModelRef, Outcome, Ready, RouteInput};
use crate::log;
use crate::settings::AiSettings;

/// Claude and OpenAI search the web themselves.
pub const SYSTEM_PROMPT_SEARCH: &str = "You are Shrimpy, a personal AI assistant living at the top of the user's screen. \
You have web search access and can help with absolutely anything — research, coding, finding places, recommendations, tasks, questions. \
Respond in the user's language. Be thorough and complete — use as much detail as the task requires. \
No markdown formatting (no **, no ##, no bullet dashes). Use plain text with line breaks.";

/// Every other model: no claim of web access it doesn't have.
pub const SYSTEM_PROMPT_PLAIN: &str = "You are Shrimpy, a personal AI assistant living at the top of the user's screen. \
You can help with research, coding, recommendations, tasks and questions. \
Respond in the user's language. Be thorough and complete — use as much detail as the task requires. \
No markdown formatting (no **, no ##, no bullet dashes). Use plain text with line breaks.";

/// The line after the companion's text for a provider that searches the web itself (the Mac's words).
pub const WEB_LINE: &str = "You can search the web.";

/// The head of the Claude plan's preamble: the companion's text is instructions from the app, not words of the user.
pub const CLAUDE_HEAD: &str = "From NotchMeow, the app this chat runs in (instructions and context for you, not words of the user):";

/// The companion's text is cut to this many characters (never bytes) before it goes to any model.
pub const SYSTEM_MAX_CHARS: usize = 32_000;

/// A saved conversation opened in the chat keeps its last this many messages, each cut to `LOADED_TEXT_MAX` characters.
const LOADED_TURNS_MAX: usize = 1_000;
const LOADED_TEXT_MAX: usize = 100_000;

/// One saved message as the page sends it on opening a conversation (`ai_load_turns`).
#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct LoadTurn {
    pub role: String,
    pub text: String,
}

/// The words of a saved conversation, as the chat's history: user and assistant messages with text in them, the last
/// `LOADED_TURNS_MAX`, each cut to `LOADED_TEXT_MAX` characters. Files are never restored.
pub fn loaded_turns(raw: &[LoadTurn]) -> Vec<Turn> {
    let kept: Vec<&LoadTurn> = raw.iter().filter(|t| !t.text.trim().is_empty() && matches!(t.role.as_str(), "user" | "assistant")).collect();
    kept[kept.len().saturating_sub(LOADED_TURNS_MAX)..]
        .iter()
        .map(|t| {
            let text: String = t.text.chars().take(LOADED_TEXT_MAX).collect();
            if t.role == "user" { Turn::user(text, Vec::new()) } else { Turn::assistant(text) }
        })
        .collect()
}

/// The companion's text as the models get it, cut to `SYSTEM_MAX_CHARS` characters.
fn companion_text(text: &str) -> String {
    text.chars().take(SYSTEM_MAX_CHARS).collect()
}

/// What a request tells a model, one line per message part, for "what the companion sent" (memory only). A file or an image
/// is named, never shown: its body is not in the line.
pub fn sent_lines(r: &ChatRequest) -> Vec<String> {
    let mut lines = vec![format!("system: {}", r.system)];
    for m in &r.messages {
        let who = if m.role == Role::User { "user" } else { "assistant" };
        for part in &m.parts {
            let text = match part {
                Part::Text(t) => t.clone(),
                Part::FileText { name, .. } | Part::Pdf { name, .. } => format!("[file {name}]"),
                Part::Image { .. } => "[image]".to_string(),
            };
            lines.push(format!("{who}: {text}"));
        }
    }
    lines
}

/// The Claude plan's preamble: the companion's text under its head, then the recap of a session started afresh, joined by a
/// blank line. None when there is neither.
fn claude_preamble(system: Option<&str>, recap: Option<String>) -> Option<String> {
    let head = system.map(|s| format!("{CLAUDE_HEAD}\n{}", companion_text(s)));
    let parts: Vec<String> = [head, recap].into_iter().flatten().filter(|p| !p.is_empty()).collect();
    (!parts.is_empty()).then(|| parts.join("\n\n"))
}

/// A quick action's turn (Fix or Rewrite): the chat's settings, keys and servers, with the quick action's own system text, its own
/// `sent` (so "What the AI saw last" stays the chat's) and a Claude plan session of its own: No tools, a new id, starting from the chat's status. The
/// chat's conversation, session and level are never handed to it.
pub fn quick_env(mut env: Env, system: &str, status: claude_cli::Status) -> Env {
    env.system = Some(system.to_string()).filter(|s| !s.is_empty());
    env.sent = Arc::new(Mutex::new(Vec::new()));
    env.claude = Arc::new(Mutex::new(ClaudeChat { level: claude_code::Level::NoTools, status, ..ClaudeChat::default() }));
    env
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Feature {
    Chat,
    Files,
}

impl AiSettings {
    pub fn choice(&self, feature: Feature) -> &Choice {
        match feature {
            Feature::Chat => &self.chat,
            Feature::Files => &self.files,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct FileRef {
    pub name: String,
    pub path: PathBuf,
}

/// What `attachments::prepare` made of one message's files for one reader.
#[derive(Debug, Clone, PartialEq)]
pub struct PreparedFiles {
    reader: Reader,
    files: Vec<Prepared>,
}

/// One message of the conversation. Files stay as references and are shaped for
/// whichever model reads them, so a fallback model gets them in its own format.
#[derive(Debug, Clone, PartialEq)]
pub struct Turn {
    pub role: Role,
    pub text: String,
    pub files: Vec<FileRef>,
    /// Filled the first time a model reads this message's files, one entry per reader. Later
    /// messages reuse it, so OCR, page rendering and base64 run once, and a file the inbox
    /// sweep has since removed no longer blocks the conversation. `Arc` keeps the per-turn
    /// clone cheap when a 25 MB PDF is in there.
    prepared: Vec<Arc<PreparedFiles>>,
}

impl Turn {
    pub fn user(text: String, files: Vec<FileRef>) -> Self {
        Turn { role: Role::User, text, files, prepared: Vec::new() }
    }

    pub fn assistant(text: String) -> Self {
        Turn { role: Role::Assistant, text, files: Vec::new(), prepared: Vec::new() }
    }
}

#[derive(Default)]
pub struct Conversation {
    pub turns: Vec<Turn>,
    /// Bumped on every reset: a reply still on its way to an old conversation is dropped.
    pub generation: u64,
}

impl Conversation {
    pub fn reset(&mut self) {
        self.turns.clear();
        self.generation += 1;
    }
}

/// Why a turn stopped for a reason that is not a failure of a provider or the network. These
/// are the island's own notices. They are NOT the contract's twelve `ErrorKind`s
/// (docs/AI-PROVIDERS.md): they never reach the router, and they travel as
/// `AiEvent::Problem`, never as `AiEvent::Error`. The island shows them like errors (a note
/// and the error sound), but nothing may treat them as if a provider had sent them.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ProblemKind {
    /// The model can't see images and nothing here can read the image for it.
    CantSee,
    /// A scanned PDF this platform can neither render nor read.
    ScannedPdf,
    /// A HEIC photo: Anthropic and OpenAI reject it and local servers can't decode it.
    Heic,
    /// An archive, an app, a video or a file over 25 MB.
    Rejected,
    /// A file that could not be opened.
    Unreadable,
    /// The model the user picked is no longer on its server.
    MissingModel,
    /// The server answers but has no OpenAI-compatible API yet.
    Outdated,
    /// The model finished without any text to show.
    EmptyReply,
}

/// What the island receives over the `ai_chat` channel.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(tag = "type", rename_all = "camelCase", rename_all_fields = "camelCase")]
pub enum AiEvent {
    /// A model started answering; `caption` is "cloud · Claude Sonnet 5.5". `waking`
    /// ("Waking up qwen3.5…") is shown if a local model is slow to say its first word.
    Started { provider: String, model: String, placement: Placement, caption: String, fallback: bool, waking: Option<String> },
    Delta { text: String },
    Citation { url: String, title: String },
    /// A line under the reply: a cut file, trimmed history, a fallback.
    Notice { text: String },
    /// The reply is over. `interrupted`: the stream broke; `cancelled`: Stop was pressed.
    Done { text: String, interrupted: bool, cancelled: bool },
    /// A failure of a provider or the network: `kind` is one of the contract's twelve
    /// `ErrorKind`s, spelled as in `ErrorKind::as_str`. `retry_after` is set when the island
    /// should count down and send again. `resets_at` (Unix seconds) is when a usage limit resets: the
    /// island words it in the viewer's time zone.
    Error {
        kind: ErrorKind,
        message: String,
        action: Option<Action>,
        retry_after: Option<u64>,
        #[serde(skip_serializing_if = "Option::is_none")]
        resets_at: Option<u64>,
    },
    /// Claude Code: the session this run belongs to, so its hook events are the chat's and not a pill's. `retired` is the
    /// id this turn gave up (a level change that moved the working folder).
    ClaudeSession { session_id: String, retired: Option<String> },
    /// A step Claude Code is taking, or has finished (the same `id` updates the same row).
    Step(Step),
    /// What Claude Code said about the run it started: which model, and who pays.
    Engine(EngineReport),
    /// One of the island's own notices (`ProblemKind`), not a contract error kind.
    Problem { kind: ProblemKind, message: String, action: Option<Action> },
    /// No key and no local model.
    EmptyState,
}

#[derive(Debug, Clone, PartialEq)]
pub struct TurnRequest {
    pub feature: Feature,
    pub text: String,
    pub files: Vec<FileRef>,
    /// Retry: drop the last reply and answer the last message again.
    pub regenerate: bool,
    /// A quick Explain that starts its chat: the chat is held at no tools until the level picker is used.
    pub quick: bool,
}

/// Everything a turn reads. Built from the app state for each turn; tests build it by hand.
pub struct Env {
    pub settings: AiSettings,
    /// Provider id (anthropic, openai, google, custom) → key. Rust-side only. `None` means "has a
    /// key, value not read": what the display `Env` knows, and it is never sent anywhere.
    pub keys: HashMap<String, Option<String>>,
    /// The last discovery.
    pub servers: Vec<Server>,
    /// What discovery checks when Auto needs a local model.
    pub probes: Vec<Probe>,
    /// The debug-only cloud redirect (`catalog::debug_override()`).
    pub cloud_override: Option<String>,
    /// The chat's Claude Code session, level and last status.
    pub claude: Arc<Mutex<ClaudeChat>>,
    /// Model lists already fetched, for display names and Google's default.
    pub models: HashMap<String, Vec<ModelInfo>>,
    /// Shorter limits for tests; `None` uses the spec's.
    pub timeouts: Option<Timeouts>,
    /// The companion's text for this turn (the page's `promptOf`, cut here). `None` keeps the built-in prompt.
    pub system: Option<String>,
    /// What the last request said, one line per message part (memory only). Shared with `AiState`.
    pub sent: Arc<Mutex<Vec<String>>>,
}

impl Env {
    /// The quick look for a model server a turn needs right now. By default this computer only, with
    /// the 0.3 s probe (Auto needs a local model): a server the user added on another network keeps
    /// what the last full scan found, so a slow link can't flip it to "off" here. `Some("custom")`:
    /// the user explicitly chose the added server, so that one server is looked for again with its
    /// own 2 s probe and nothing else is scanned.
    pub(crate) async fn rediscover(&mut self, wanted: Option<&str>) {
        let added = wanted == Some("custom");
        let here = |p: &Probe| discovery::describe(&p.provider, &p.base_url).1 == Placement::Local;
        let probes = self.probes.iter().filter(|p| if added { p.provider == "custom" } else { here(p) }).cloned().collect();
        let limit = if added { catalog::ADDED_PROBE_MS } else { catalog::PROBE_MS };
        for found in discovery::discover(probes, std::time::Duration::from_millis(limit)).await {
            match self.servers.iter_mut().find(|s| s.provider == found.provider && s.base_url == found.base_url) {
                Some(old) => *old = found,
                None => self.servers.push(found),
            }
        }
    }

    fn timeouts(&self, placement: Placement) -> Timeouts {
        self.timeouts.unwrap_or_else(|| Timeouts::for_placement(placement))
    }
}

/// Running servers with models, each with its last-used (or first) model, in discovery order.
pub fn ready_list(env: &Env) -> Vec<Ready> {
    env.servers
        .iter()
        .filter(|s| s.status == ServerStatus::Running && !s.models.is_empty())
        .map(|s| {
            let remembered = env.settings.local_models.get(&s.provider).filter(|m| s.models.iter().any(|x| &x.id == *m));
            Ready {
                provider: s.provider.clone(),
                model: remembered.cloned().unwrap_or_else(|| s.models[0].id.clone()),
                placement: s.placement,
            }
        })
        .collect()
}

/// The cloud providers Auto may use: those with a key, and Claude Code once the user connected it and the last check found
/// it signed in.
fn ready_clouds(env: &Env) -> Vec<String> {
    let mut ready: Vec<String> = catalog::CLOUD_ORDER.iter().filter(|p| env.keys.contains_key(**p)).map(|p| p.to_string()).collect();
    if env.settings.claude_code_enabled && env.claude.lock().unwrap().status.is_ready() {
        ready.push("claudeCode".to_string());
    }
    ready
}

pub fn route_input(env: &Env, feature: Feature) -> RouteInput {
    RouteInput {
        setting: env.settings.choice(feature).clone(),
        preferred_cloud: env.settings.preferred_cloud.clone(),
        keys: ready_clouds(env),
        online: true,
        local_ready: ready_list(env),
        last_used_local: env.settings.last_used_local.clone(),
        apple_ready: false,
        failure: None,
    }
}

/// One model, ready to be called.
#[derive(Debug, Clone, PartialEq)]
pub struct Target {
    pub endpoint: Endpoint,
    pub model: String,
    /// What the caption shows: the model's display name, or its id.
    pub model_name: String,
    pub vision: bool,
    pub context_tokens: Option<u64>,
    host: String,
    /// Claude Code: the run to make (it has no URL, no key and no server).
    pub claude: Option<ClaudeTarget>,
}

/// One Claude Code turn: the process to run, and what the chat must learn about its session.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClaudeTarget {
    pub run: Run,
    pub session_id: String,
    pub retired: Option<String>,
    /// The folder the turn runs in, told to the session when Claude Code reports it.
    pub folder: String,
    /// The session is new in the middle of a chat: the first message carries a recap.
    pub needs_recap: bool,
}

impl Target {
    pub fn who(&self) -> Who {
        Who { provider: self.endpoint.provider.clone(), name: self.endpoint.name.clone() }
    }

    /// "cloud · Claude Sonnet 5.5", "local · qwen3.5:2b", "network · llama3 @ studio-pc".
    pub fn caption(&self) -> String {
        match self.endpoint.placement {
            Placement::Cloud => format!("cloud · {}", self.model_name),
            Placement::Local => format!("local · {}", self.model),
            Placement::Network => format!("network · {} @ {}", self.model, self.host),
        }
    }

}

pub fn make_provider(endpoint: Endpoint) -> Box<dyn ModelProvider> {
    match catalog::get(&endpoint.provider).map(|p| p.api) {
        Some(Api::Anthropic) => Box::new(Anthropic::new(endpoint)),
        Some(Api::OpenAIResponses) => Box::new(OpenAI::new(endpoint)),
        _ => Box::new(OpenAICompat::new(endpoint)),
    }
}

enum TargetError {
    Failed(AiError, Who),
    Event(AiEvent),
}

fn problem(kind: ProblemKind, message: String, action: Option<Action>) -> AiEvent {
    AiEvent::Problem { kind, message, action }
}

/// The endpoint and model for a provider. Cloud needs its key; a local server is
/// looked for again when the last discovery didn't see it running.
async fn target_for(env: &mut Env, provider: &str, model: Option<String>) -> Result<Target, TargetError> {
    if provider == "claudeCode" {
        return Ok(claude_target(env, model));
    }
    if catalog::is_cloud(provider) {
        let def = catalog::get(provider).unwrap();
        let who = Who { provider: provider.into(), name: def.name.into() };
        let Some(key) = env.keys.get(provider).cloned().flatten() else {
            let missing = AiError { code: Some(errors::MISSING_KEY.into()), ..AiError::new(ErrorKind::Auth) };
            return Err(TargetError::Failed(missing, who));
        };
        let endpoint = Endpoint {
            provider: provider.into(),
            name: def.name.into(),
            base_url: catalog::base_url(provider, env.cloud_override.as_deref()).unwrap_or_default(),
            key: Some(key),
            placement: Placement::Cloud,
            timeouts: env.timeouts(Placement::Cloud),
        };
        let known = env.models.get(provider).cloned().unwrap_or_default();
        let chosen = model
            .or_else(|| env.settings.cloud_models.get(provider).cloned())
            .or_else(|| catalog::default_model(provider, &known));
        let model = match chosen {
            Some(m) => m,
            None => {
                let list = make_provider(endpoint.clone()).list_models().await.map_err(|e| TargetError::Failed(e, who.clone()))?;
                env.models.insert(provider.into(), list.clone());
                catalog::default_model(provider, &list).ok_or_else(|| TargetError::Failed(AiError::new(ErrorKind::BadRequest), who.clone()))?
            }
        };
        let model_name = env
            .models
            .get(provider)
            .and_then(|l| l.iter().find(|m| m.id == model))
            .map(|m| m.display_name.clone())
            .unwrap_or_else(|| model.clone());
        return Ok(Target { endpoint, model, model_name, vision: true, context_tokens: None, host: String::new(), claude: None });
    }

    let running = |env: &Env| env.servers.iter().find(|s| s.provider == provider && s.status == ServerStatus::Running).cloned();
    if running(env).is_none() {
        env.rediscover(Some(provider)).await;
    }
    let server = match running(env) {
        Some(s) => s,
        None => {
            let seen = env.servers.iter().find(|s| s.provider == provider);
            if let Some(s) = seen.filter(|s| s.status == ServerStatus::Outdated) {
                let w = errors::outdated_copy(&s.name);
                return Err(TargetError::Event(problem(ProblemKind::Outdated, w.text, w.action)));
            }
            let name = seen.map(|s| s.name.clone()).or_else(|| catalog::get(provider).map(|d| d.name.to_string())).unwrap_or_default();
            return Err(TargetError::Failed(AiError::new(ErrorKind::Unreachable), Who { provider: provider.into(), name }));
        }
    };
    let who = Who { provider: provider.into(), name: server.name.clone() };
    let model = match model {
        Some(m) if server.models.iter().any(|x| x.id == m) => m,
        // An explicit choice is never swapped for another model behind the user's back.
        Some(m) => {
            let w = errors::missing_model_copy(&m, &server.name);
            return Err(TargetError::Event(problem(ProblemKind::MissingModel, w.text, w.action)));
        }
        None => server
            .models
            .first()
            .map(|m| m.id.clone())
            .ok_or_else(|| TargetError::Failed(AiError::new(ErrorKind::BadRequest), who.clone()))?,
    };
    let info = server.models.iter().find(|m| m.id == model);
    Ok(Target {
        endpoint: Endpoint {
            provider: provider.into(),
            name: server.name.clone(),
            base_url: server.base_url.clone(),
            key: if provider == "custom" { env.keys.get("custom").cloned().flatten() } else { None },
            placement: server.placement,
            timeouts: env.timeouts(server.placement),
        },
        model_name: info.map(|m| m.display_name.clone()).unwrap_or_else(|| model.clone()),
        context_tokens: info.and_then(|m| m.context_tokens),
        vision: info.is_some_and(|m| m.capabilities.vision),
        model,
        host: server.host.clone(),
        claude: None,
    })
}

/// Claude Code: the chat's session plans the turn (resume it, or start a new one when the level moved the folder).
fn claude_target(env: &Env, model: Option<String>) -> Target {
    let alias = model.filter(|m| claude_code::MODELS.contains(&m.as_str())).unwrap_or_else(|| env.settings.claude_code_model.clone());
    let (plan, executable, chat_folder) = {
        let mut chat = env.claude.lock().unwrap();
        let chat_folder = chat.chat_folder.clone().unwrap_or_else(claude_chat::chat_folder);
        // A quick hold plans no tools whatever level the chat is at; a pick in the picker ends it.
        let level = if chat.quick_hold { claude_code::Level::NoTools } else { chat.level.clone() };
        let executable = chat.status.executable.clone().unwrap_or_default();
        (chat.session.plan(&level, &alias, &chat_folder, Platform::current(), claude_chat::new_id), executable, chat_folder)
    };
    let label = format!("{}{}", alias[..1].to_uppercase(), &alias[1..]);
    let run = Run {
        executable,
        leading_args: Vec::new(),
        turn: plan.turn,
        chat_folder,
        preamble: None,
        // Not `std::env::vars()`: it panics on a variable that is not Unicode.
        base_env: claude_cli::current_environment().into_iter().collect(),
        timings: ClaudeTimings::default(),
    };
    Target {
        endpoint: Endpoint {
            provider: "claudeCode".into(),
            name: "Claude plan".into(),
            base_url: String::new(),
            key: None,
            placement: Placement::Cloud,
            timeouts: env.timeouts(Placement::Cloud),
        },
        model: alias,
        model_name: format!("Claude plan · {label}"),
        vision: true,
        context_tokens: None,
        host: String::new(),
        claude: Some(ClaudeTarget { session_id: run.turn.session_id.clone(), retired: plan.retired, folder: plan.folder, needs_recap: plan.needs_recap, run }),
    }
}

fn prepare_event(err: PrepareError) -> AiEvent {
    match err {
        PrepareError::CantSee => problem(ProblemKind::CantSee, errors::CANT_SEE.into(), Some(Action::ChooseModel)),
        PrepareError::ScannedPdf => problem(ProblemKind::ScannedPdf, errors::scanned_pdf_copy().into(), None),
        PrepareError::Heic => problem(ProblemKind::Heic, errors::HEIC.into(), None),
        PrepareError::Rejected(r) => problem(ProblemKind::Rejected, attachments::reject_message(r).into(), None),
        PrepareError::Unreadable => problem(ProblemKind::Unreadable, "I couldn't read that file.".into(), None),
    }
}

/// One file shaped for one reader, off the async threads: OCR, page rendering and base64 are slow.
async fn prepare_one(file: &FileRef, reader: &Reader) -> Result<Prepared, PrepareError> {
    let (path, name, reader) = (file.path.clone(), file.name.clone(), reader.clone());
    tokio::task::spawn_blocking(move || attachments::prepare(&path, &name, &reader))
        .await
        .unwrap_or(Err(PrepareError::Unreadable))
}

/// Keeps what was prepared on its message, so the next message doesn't prepare it again.
fn remember(conv: &Mutex<Conversation>, generation: u64, index: usize, files: &[FileRef], entry: Arc<PreparedFiles>) {
    let mut c = conv.lock().unwrap();
    if c.generation != generation {
        return;
    }
    if let Some(turn) = c.turns.get_mut(index).filter(|t| t.files == files) {
        turn.prepared.push(entry);
    }
}

/// The provider-neutral history, shaped for one model: each message's files prepared for it
/// (once per reader, then reused), the oldest turns dropped when the chat outgrew the model.
async fn build_request(
    target: &Target,
    turns: &[Turn],
    conv: &Mutex<Conversation>,
    generation: u64,
    companion: Option<&str>,
) -> Result<(ChatRequest, Vec<String>), AiEvent> {
    let reader = Reader {
        provider: target.endpoint.provider.clone(),
        placement: target.endpoint.placement,
        vision: target.vision,
        context_tokens: target.context_tokens,
    };
    let mut messages = Vec::new();
    let mut notices = Vec::new();
    for (i, turn) in turns.iter().enumerate() {
        let latest = i + 1 == turns.len();
        let mut parts = Vec::new();
        if !turn.files.is_empty() {
            let prepared = match turn.prepared.iter().find(|p| p.reader == reader) {
                Some(hit) => hit.clone(),
                None => {
                    let mut files = Vec::new();
                    let mut complete = true;
                    for file in &turn.files {
                        match prepare_one(file, &reader).await {
                            Ok(p) => files.push(p),
                            // A file from an earlier message that can't be read now (the inbox sweep
                            // removed it, say) must not block a new question: tell the model instead.
                            Err(_) if !latest => {
                                complete = false;
                                let note = format!("{} (no longer available)", file_label(&file.name));
                                files.push(Prepared { parts: vec![Part::Text(note)], notice: None });
                            }
                            Err(e) => return Err(prepare_event(e)),
                        }
                    }
                    let entry = Arc::new(PreparedFiles { reader: reader.clone(), files });
                    if complete {
                        remember(conv, generation, i, &turn.files, entry.clone());
                    }
                    entry
                }
            };
            for file in &prepared.files {
                if latest {
                    notices.extend(file.notice.clone());
                }
                parts.extend(file.parts.clone());
            }
        }
        if !turn.text.is_empty() {
            parts.push(Part::Text(turn.text.clone()));
        }
        messages.push(Message { role: turn.role, parts });
    }
    let searches = catalog::reads_pdf_natively(&reader.provider);
    let system = match companion {
        Some(text) => {
            let mut system = companion_text(text);
            if searches {
                system.push_str("\n\n");
                system.push_str(WEB_LINE);
            }
            system
        }
        None => (if searches { SYSTEM_PROMPT_SEARCH } else { SYSTEM_PROMPT_PLAIN }).to_string(),
    };
    let lengths: Vec<usize> = messages.iter().map(budget::message_chars).collect();
    let drop = budget::messages_to_drop(reader.placement, reader.context_tokens, system.chars().count(), &lengths);
    if drop > 0 {
        messages.drain(..drop);
        notices.push(errors::TOO_LONG.to_string());
    }
    let request = ChatRequest {
        model: target.model.clone(),
        system,
        messages,
        tools: Vec::new(),
        response_format: None,
        max_tokens: catalog::max_output_tokens(reader.placement),
    };
    Ok((request, notices))
}

enum Attempt {
    /// `cut_off`: the model stopped at the token limit, so the text may end mid-sentence.
    Answered { text: String, cut_off: bool },
    /// The model finished with nothing to show; `cut_off` says it ran out of tokens first.
    Empty { cut_off: bool },
    Interrupted(String),
    Cancelled(String),
    Refused(String),
    Failed(AiError),
    Stopped(AiEvent),
}

/// Streams one model's answer into the island.
async fn attempt(
    env: &Env,
    target: &mut Target,
    turns: &[Turn],
    conv: &Mutex<Conversation>,
    generation: u64,
    cancel: &Notify,
    fallback: bool,
    emit: &mut (dyn FnMut(AiEvent) + Send),
) -> Attempt {
    // A local model's vision and the context it runs at come from its own server, for every
    // message: the history is trimmed to that context even when no file is in it.
    if target.endpoint.placement != Placement::Cloud {
        if let Some(server) = env.servers.iter().find(|s| s.provider == target.endpoint.provider) {
            let details = discovery::details(server, &target.model).await;
            target.vision = target.vision || details.vision;
            target.context_tokens = details.context_tokens.or(target.context_tokens);
        }
    }
    let (request, notices) = match build_request(target, turns, conv, generation, env.system.as_deref()).await {
        Ok(r) => r,
        Err(event) => return Attempt::Stopped(event),
    };
    *env.sent.lock().unwrap() = sent_lines(&request);
    let claude_chat = env.claude.clone();
    let provider: Box<dyn ModelProvider> = match target.claude.as_mut() {
        Some(claude) => {
            // A session started afresh in the middle of a chat is told what was said before (the new message is last).
            let recap = if claude.needs_recap {
                let said: Vec<(Role, String)> = turns[..turns.len().saturating_sub(1)].iter().map(|t| (t.role, t.text.clone())).collect();
                claude_chat::recap(&said)
            } else {
                None
            };
            claude.run.preamble = claude_preamble(env.system.as_deref(), recap);
            emit(AiEvent::ClaudeSession { session_id: claude.session_id.clone(), retired: claude.retired.clone() });
            Box::new(ClaudeCode::new(claude.run.clone()))
        }
        None => make_provider(target.endpoint.clone()),
    };
    let claude_run = target.claude.as_ref().map(|c| (c.session_id.clone(), c.folder.clone()));
    log::line(format!("ai start provider={} placement={} fallback={fallback}", provider.id(), provider.placement().as_str()));
    emit(AiEvent::Started {
        provider: target.endpoint.provider.clone(),
        model: target.model.clone(),
        placement: target.endpoint.placement,
        caption: target.caption(),
        fallback,
        waking: (target.endpoint.placement != Placement::Cloud).then(|| errors::waking_copy(&target.model)),
    });
    for text in notices {
        emit(AiEvent::Notice { text });
    }
    let mut shown = String::new();
    let result = {
        let mut sink = |chunk: ChatChunk| match chunk {
            ChatChunk::Text(text) => {
                shown.push_str(&text);
                emit(AiEvent::Delta { text });
            }
            ChatChunk::Citation { url, title } => emit(AiEvent::Citation { url, title }),
            ChatChunk::Step(step) => emit(AiEvent::Step(step)),
            ChatChunk::Engine(report) => {
                // Claude Code has made the session: the next turn resumes it, from the same folder.
                if let Some((session_id, folder)) = &claude_run {
                    claude_chat.lock().unwrap().confirm(session_id, folder);
                }
                emit(AiEvent::Engine(report));
            }
            _ => {}
        };
        tokio::select! {
            r = provider.stream(&request, &mut sink) => Some(r),
            _ = cancel.notified() => None,
        }
    };
    match result {
        None => Attempt::Cancelled(shown),
        Some(Err(e)) => {
            // A run refused for its tools was killed right after `init`: Claude Code may have recorded the session, so the
            // chat plans a fresh one next (told the chat so far) instead of reusing its id.
            if let (Some((session_id, _)), Some(claude_code::TOOLS_PRESENT)) = (&claude_run, e.code.as_deref()) {
                claude_chat.lock().unwrap().refuse(session_id);
            }
            Attempt::Failed(e)
        }
        Some(Ok(agg)) => classify(agg, shown),
    }
}

/// The reply as the user saw it. By the contract's rule an unclosed `<think>` stays in the
/// aggregate (a model that ran out of tokens mid-thought), but it must never become the reply.
fn visible_text(aggregate_text: String, shown: String) -> String {
    if aggregate_text.contains("<think>") {
        shown
    } else {
        aggregate_text
    }
}

fn classify(agg: Aggregate, shown: String) -> Attempt {
    if agg.finish == Some(Finish::Refusal) {
        return Attempt::Refused(agg.refusal.unwrap_or_default());
    }
    let cut_off = agg.finish == Some(Finish::Length);
    let text = visible_text(agg.text, shown);
    // A refusal with nothing to show is still a refusal, also when the stream broke after it
    // (the aggregate then carries an error and no finish): never a failure that falls back.
    if text.trim().is_empty() && agg.refusal.is_some() {
        return Attempt::Refused(agg.refusal.unwrap_or_default());
    }
    match agg.error {
        // No text at all is a failure, never an empty reply in the history.
        None if text.trim().is_empty() => Attempt::Empty { cut_off },
        None => Attempt::Answered { text, cut_off },
        // Some text arrived: keep it and mark it, whatever broke the stream.
        Some(_) if !text.trim().is_empty() => Attempt::Interrupted(text),
        // Nothing arrived: a failure like any other.
        Some(ErrorKind::Interrupted) => Attempt::Failed(AiError::new(ErrorKind::Server)),
        Some(kind) => Attempt::Failed(AiError::new(kind)),
    }
}

fn error_event(err: &AiError, who: &Who) -> AiEvent {
    let w = errors::error_copy(err.kind, who, Some(err));
    let countdown = matches!(err.kind, ErrorKind::RateLimited | ErrorKind::Overloaded);
    AiEvent::Error {
        kind: err.kind,
        message: w.text,
        action: w.action,
        retry_after: countdown.then(|| err.retry_after.unwrap_or(errors::DEFAULT_RETRY_SECONDS)),
        resets_at: err.resets_at,
    }
}

fn log_failure(err: &AiError, who: &Who) {
    log::line(format!(
        "ai error provider={} kind={} status={} request-id={}",
        who.provider,
        err.kind.as_str(),
        err.status.map_or("-".to_string(), |s| s.to_string()),
        err.request_id.as_deref().unwrap_or("-")
    ));
}

/// A local server that stopped answering is forgotten, so the next message looks again.
fn forget_if_down(env: &mut Env, err: &AiError, who: &Who) {
    if err.kind == ErrorKind::Unreachable && !catalog::is_cloud(&who.provider) {
        if let Some(s) = env.servers.iter_mut().find(|s| s.provider == who.provider) {
            s.status = ServerStatus::Off;
        }
    }
}

/// A turn that failed leaves no half turn behind: the message it pushed is taken back. A
/// retry pushed no message (`pushed` is false): the question it answers again stays.
fn undo_user(conv: &Mutex<Conversation>, generation: u64, pushed: bool) {
    let mut c = conv.lock().unwrap();
    if pushed && c.generation == generation && c.turns.last().map(|t| t.role) == Some(Role::User) {
        c.turns.pop();
    }
}

fn push_reply(conv: &Mutex<Conversation>, generation: u64, text: &str) {
    let mut c = conv.lock().unwrap();
    if c.generation == generation {
        c.turns.push(Turn::assistant(text.to_string()));
    }
}

/// Settles a finished attempt. Returns the failure when the router may still act on it.
fn settle(
    env: &mut Env,
    conv: &Mutex<Conversation>,
    generation: u64,
    pushed: bool,
    target: &Target,
    outcome: Attempt,
    emit: &mut (dyn FnMut(AiEvent) + Send),
) -> Option<AiError> {
    match outcome {
        Attempt::Answered { text, cut_off } => {
            push_reply(conv, generation, &text);
            if target.endpoint.placement != Placement::Cloud {
                let (p, m) = (target.endpoint.provider.clone(), target.model.clone());
                env.settings.local_models.insert(p.clone(), m.clone());
                env.settings.last_used_local = Some(ModelRef { provider: p, model: m });
            }
            log::line(format!("ai done provider={} cut-off={cut_off}", target.endpoint.provider));
            if cut_off {
                // Worth keeping, but it stopped at the token limit and may end mid-sentence.
                emit(AiEvent::Notice { text: errors::CUT_OFF.into() });
            }
            emit(AiEvent::Done { text, interrupted: false, cancelled: false });
            None
        }
        Attempt::Empty { cut_off } => {
            // No text at all: nothing joins the history and no `Done` follows, so the island
            // plays the error sound, not the finish one.
            undo_user(conv, generation, pushed);
            log::line(format!("ai empty provider={} cut-off={cut_off}", target.endpoint.provider));
            let (message, action) = if cut_off {
                (errors::RAN_OUT_OF_ROOM, Some(Action::ChooseModel))
            } else {
                (errors::EMPTY_REPLY, None)
            };
            emit(problem(ProblemKind::EmptyReply, message.into(), action));
            None
        }
        Attempt::Interrupted(text) => {
            push_reply(conv, generation, &text);
            log::line(format!("ai interrupted provider={}", target.endpoint.provider));
            emit(AiEvent::Done { text, interrupted: true, cancelled: false });
            None
        }
        Attempt::Cancelled(text) => {
            if text.is_empty() {
                undo_user(conv, generation, pushed);
            } else {
                push_reply(conv, generation, &text);
            }
            log::line(format!("ai cancelled provider={}", target.endpoint.provider));
            emit(AiEvent::Done { text, interrupted: false, cancelled: true });
            None
        }
        Attempt::Refused(text) => {
            undo_user(conv, generation, pushed);
            log::line(format!("ai refusal provider={}", target.endpoint.provider));
            let message = if text.trim().is_empty() { errors::error_copy(ErrorKind::Refusal, &target.who(), None).text } else { text };
            emit(AiEvent::Error { kind: ErrorKind::Refusal, message, action: None, retry_after: None, resets_at: None });
            None
        }
        Attempt::Stopped(event) => {
            undo_user(conv, generation, pushed);
            emit(event);
            None
        }
        Attempt::Failed(err) => {
            log_failure(&err, &target.who());
            Some(err)
        }
    }
}

/// Files stay on File questions: once any message of the conversation holds a file, every turn
/// uses that setting, whatever the webview asked for.
fn effective_feature(asked: Feature, turns: &[Turn]) -> Feature {
    if turns.iter().any(|t| !t.files.is_empty()) { Feature::Files } else { asked }
}

/// One turn, start to finish. Never panics, never blocks an agent: every outcome
/// is an event.
pub async fn run_turn(
    env: &mut Env,
    conv: &Mutex<Conversation>,
    request: TurnRequest,
    cancel: &Notify,
    emit: &mut (dyn FnMut(AiEvent) + Send),
) {
    // A retry answers the message already there; only a new message is taken back on failure.
    let pushed = !request.regenerate;
    let (turns, generation) = {
        let mut c = conv.lock().unwrap();
        if request.regenerate {
            if c.turns.last().map(|t| t.role) == Some(Role::Assistant) {
                c.turns.pop();
            }
        } else {
            c.turns.push(Turn::user(request.text.clone(), request.files.clone()));
        }
        (c.turns.clone(), c.generation)
    };
    if turns.last().map(|t| t.role) != Some(Role::User) {
        emit(AiEvent::Done { text: String::new(), interrupted: false, cancelled: true });
        return;
    }
    // A quick Explain starts its chat held at no tools (memory only, see `ClaudeChat::quick_hold`).
    if request.quick {
        env.claude.lock().unwrap().quick_hold = true;
    }

    let feature = effective_feature(request.feature, &turns);
    let mut input = route_input(env, feature);
    if input.setting.is_auto() && router::cloud_choice(&input).is_none() && input.local_ready.is_empty() {
        env.rediscover(None).await;
        input = route_input(env, feature);
    }
    let first = router::route(&input);
    let Some(primary) = first.primary.clone().filter(|_| first.outcome != Outcome::EmptyState) else {
        undo_user(conv, generation, pushed);
        emit(AiEvent::EmptyState);
        return;
    };
    let primary_model = match &input.setting {
        Choice::Explicit(m) => Some(m.model.clone()),
        Choice::Auto(_) if catalog::is_cloud(&primary) => None,
        Choice::Auto(_) => router::local_choice(&input).map(|r| r.model),
    };

    let failure = match target_for(env, &primary, primary_model).await {
        Ok(mut target) => {
            let outcome = attempt(env, &mut target, &turns, conv, generation, cancel, false, emit).await;
            match settle(env, conv, generation, pushed, &target, outcome, emit) {
                None => return,
                Some(err) => (err, target.who()),
            }
        }
        Err(TargetError::Event(event)) => {
            undo_user(conv, generation, pushed);
            emit(event);
            return;
        }
        Err(TargetError::Failed(err, who)) => {
            log_failure(&err, &who);
            (err, who)
        }
    };

    // The router decides what a failure means: one local retry, a countdown, or an error.
    let (err, who) = failure;
    forget_if_down(env, &err, &who);
    let mut after = input.clone();
    after.failure = Some(err.kind);
    if after.setting.is_auto() && err.kind.is_temporary() && catalog::is_cloud(&primary) && after.local_ready.is_empty() {
        env.rediscover(None).await;
        after.local_ready = ready_list(env);
    }
    let decision = router::route(&after);
    // Claude Code took steps before it failed: they stay done, and no other model is asked the same question.
    if decision.outcome != Outcome::Fallback || err.after_steps {
        undo_user(conv, generation, pushed);
        emit(error_event(&err, &who));
        return;
    }
    let Some(local) = router::local_choice(&after) else {
        undo_user(conv, generation, pushed);
        emit(error_event(&err, &who));
        return;
    };
    log::line(format!("ai fallback from={primary} to={}", local.provider));
    let fallback = match target_for(env, &local.provider, Some(local.model.clone())).await {
        Ok(t) => t,
        Err(TargetError::Event(event)) => {
            undo_user(conv, generation, pushed);
            emit(event);
            return;
        }
        Err(TargetError::Failed(e, w)) => {
            forget_if_down(env, &e, &w);
            undo_user(conv, generation, pushed);
            emit(error_event(&e, &w));
            return;
        }
    };
    emit(AiEvent::Notice { text: errors::fallback_copy(&primary, &fallback.model) });
    let mut fallback = fallback;
    let outcome = attempt(env, &mut fallback, &turns, conv, generation, cancel, true, emit).await;
    if let Some(e) = settle(env, conv, generation, pushed, &fallback, outcome, emit) {
        forget_if_down(env, &e, &fallback.who());
        undo_user(conv, generation, pushed);
        emit(error_event(&e, &fallback.who()));
    }
}

/// What a feature resolves to right now, for the model chip, the settings line
/// ("Claude Sonnet · falls back to Local · qwen3.5:2b") and the drop card.
/// Makes no network call.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Resolution {
    pub empty: bool,
    pub auto: bool,
    pub provider: Option<String>,
    pub model: Option<String>,
    pub placement: Option<Placement>,
    /// "Claude Sonnet 5.5", "qwen3.5:2b".
    pub model_name: Option<String>,
    /// The drop card: "Claude", "Local · qwen3.5:2b".
    pub reader: Option<String>,
    /// Auto's local retry: "Local · qwen3.5:2b".
    pub fallback: Option<String>,
}

pub fn resolve(env: &Env, feature: Feature) -> Resolution {
    let input = route_input(env, feature);
    let decision = router::route(&input);
    let mut res = Resolution {
        empty: decision.outcome == Outcome::EmptyState,
        auto: input.setting.is_auto(),
        provider: None,
        model: None,
        placement: None,
        model_name: None,
        reader: None,
        fallback: None,
    };
    let Some(primary) = decision.primary else { return res };
    let local_reader = |r: &Ready| match r.placement {
        Placement::Network => {
            let host = env.servers.iter().find(|s| s.provider == r.provider).map(|s| s.host.clone()).unwrap_or_default();
            format!("Network · {} @ {host}", r.model)
        }
        _ => format!("Local · {}", r.model),
    };
    let model = match &input.setting {
        Choice::Explicit(m) => Some(m.model.clone()),
        Choice::Auto(_) if primary == "claudeCode" => Some(env.settings.claude_code_model.clone()),
        Choice::Auto(_) if catalog::is_cloud(&primary) => env
            .settings
            .cloud_models
            .get(&primary)
            .cloned()
            .or_else(|| catalog::default_model(&primary, env.models.get(&primary).map(Vec::as_slice).unwrap_or(&[]))),
        Choice::Auto(_) => router::local_choice(&input).map(|r| r.model),
    };
    let placement = decision.label.unwrap_or(Placement::Local);
    res.model_name = model.as_ref().map(|m| {
        env.models
            .get(&primary)
            .and_then(|l| l.iter().find(|x| &x.id == m))
            .map(|x| x.display_name.clone())
            .unwrap_or_else(|| m.clone())
    });
    res.reader = Some(match placement {
        Placement::Cloud => catalog::brand(&primary).to_string(),
        _ => local_reader(&Ready { provider: primary.clone(), model: model.clone().unwrap_or_default(), placement }),
    });
    if res.auto && placement == Placement::Cloud {
        res.fallback = router::local_choice(&input).map(|r| local_reader(&r));
    }
    res.provider = Some(primary);
    res.model = model;
    res.placement = Some(placement);
    res
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ai::provider::Capabilities;
    use crate::ai::testkit::{self, FakeServer};

    fn running(provider: &str, base: &str, placement: Placement) -> Server {
        Server {
            provider: provider.into(),
            name: catalog::get(provider).map(|d| d.name).unwrap_or("x").into(),
            base_url: base.into(),
            host: "127.0.0.1".into(),
            placement,
            status: ServerStatus::Running,
            models: vec![ModelInfo::named("llama3.2")],
            unencrypted: false,
        }
    }

    fn env(keys: &[&str], cloud: Option<&FakeServer>, local: Option<&FakeServer>) -> Env {
        Env {
            settings: AiSettings::default(),
            claude: Default::default(),
            keys: keys.iter().map(|k| (k.to_string(), Some("test-key".to_string()))).collect(),
            servers: local.map(|f| vec![running("ollama", &f.base, Placement::Local)]).unwrap_or_default(),
            probes: Vec::new(),
            cloud_override: cloud.map(|f| f.base.clone()),
            models: HashMap::new(),
            timeouts: Some(Timeouts {
                connect: std::time::Duration::from_secs(2),
                first_token: std::time::Duration::from_secs(5),
                idle: std::time::Duration::from_secs(5),
            }),
            system: None,
            sent: Default::default(),
        }
    }

    fn ask(text: &str) -> TurnRequest {
        TurnRequest { feature: Feature::Chat, text: text.into(), files: vec![], regenerate: false, quick: false }
    }

    async fn turn(env: &mut Env, conv: &Mutex<Conversation>, req: TurnRequest) -> Vec<AiEvent> {
        let cancel = Notify::new();
        let mut events = Vec::new();
        run_turn(env, conv, req, &cancel, &mut |e| events.push(e)).await;
        events
    }

    fn done_text(events: &[AiEvent]) -> Option<String> {
        events.iter().find_map(|e| match e {
            AiEvent::Done { text, .. } => Some(text.clone()),
            _ => None,
        })
    }

    /// An Ollama-like server whose one reply streams these chat-completions text deltas and
    /// then `finish_reason`. For the replies the fake model server can't produce.
    fn canned_reply(deltas: &[&str], finish: &str) -> Env {
        let mut body = String::new();
        for d in deltas {
            let event = serde_json::json!({ "choices": [{ "index": 0, "delta": { "content": d } }] });
            body.push_str(&format!("data: {event}\n\n"));
        }
        let last = serde_json::json!({ "choices": [{ "index": 0, "delta": {}, "finish_reason": finish }] });
        body.push_str(&format!("data: {last}\n\ndata: [DONE]\n\n"));
        let base = testkit::canned_server(200, "text/event-stream", &body);
        let mut env = env(&[], None, None);
        env.servers = vec![running("ollama", &base, Placement::Local)];
        env
    }

    // ── Claude Code ──────────────────────────────────────────────────────────────────────────────────────────────────

    /// A `claude` that is a shell script around the fake, with its transcript and log fixed in the script itself, so no
    /// test touches the process environment (tests run in parallel).
    #[cfg(unix)]
    fn claude_script(dir: &testkit::TempDir, transcript: &str, name: &str) -> (String, String) {
        use std::os::unix::fs::PermissionsExt;
        let python = testkit::python();
        let log = dir.path().join(format!("{name}.jsonl")).to_string_lossy().to_string();
        let body = format!(
            "#!/bin/sh\nexport NM_FAKE_CLAUDE_TRANSCRIPT='{}'\nexport NM_FAKE_CLAUDE_LOG='{log}'\nexec {} {} '{}' \"$@\"\n",
            transcript,
            python.get_program().to_string_lossy(),
            python.get_args().map(|a| a.to_string_lossy().to_string()).collect::<Vec<_>>().join(" "),
            testkit::fixtures_dir().join("claude-code/fake_claude.py").display(),
        );
        let path = dir.path().join(name);
        std::fs::write(&path, body).unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).unwrap();
        (path.to_string_lossy().to_string(), log)
    }

    #[cfg(unix)]
    fn transcript(name: &str) -> String {
        testkit::fixtures_dir().join("claude-code/transcripts").join(name).to_string_lossy().to_string()
    }

    /// An Env where the user connected "Use my Claude plan" and Claude Code is signed in.
    fn claude_env(dir: &testkit::TempDir, exe: &str) -> Env {
        let mut env = env(&[], None, None);
        env.settings.claude_code_enabled = true;
        env.settings.preferred_cloud = "claudeCode".into();
        {
            let mut chat = env.claude.lock().unwrap();
            chat.status = crate::ai::claude_cli::Status {
                state: crate::ai::claude_cli::State::SignedIn,
                executable: Some(exe.to_string()),
                version: Some("2.1.211".into()),
                auth_method: Some("claude.ai".into()),
                shim_only: false,
                needs_git: false,
            };
            chat.chat_folder = Some(dir.path().join("chat").to_string_lossy().to_string());
        }
        env
    }

    #[cfg(unix)]
    fn fake_calls(log: &str) -> Vec<serde_json::Value> {
        std::fs::read_to_string(log).unwrap_or_default().lines().filter_map(|l| serde_json::from_str(l).ok()).collect()
    }

    #[test]
    fn claude_code_is_ready_only_when_connected_and_signed_in() {
        let dir = testkit::TempDir::new("claude-ready");
        let mut env = claude_env(&dir, "/x/claude");
        assert!(route_input(&env, Feature::Chat).keys.contains(&"claudeCode".to_string()));
        env.settings.claude_code_enabled = false;
        assert!(!route_input(&env, Feature::Chat).keys.contains(&"claudeCode".to_string()), "never connected: not used");
        env.settings.claude_code_enabled = true;
        env.claude.lock().unwrap().status.state = crate::ai::claude_cli::State::SignedOut;
        assert!(!route_input(&env, Feature::Chat).keys.contains(&"claudeCode".to_string()), "signed out: not ready");
        let res = resolve(&claude_env(&dir, "/x/claude"), Feature::Chat);
        assert_eq!((res.provider.as_deref(), res.model.as_deref(), res.model_name.as_deref()), (Some("claudeCode"), Some("sonnet"), Some("sonnet")));
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn a_claude_turn_streams_steps_and_text_and_confirms_the_session() {
        let dir = testkit::TempDir::new("claude-turn");
        let _runs = testkit::claude_runs_shared();
        let (exe, log) = claude_script(&dir, &transcript("tool-use.jsonl"), "claude");
        let mut env = claude_env(&dir, &exe);
        let conv = Mutex::new(Conversation::default());
        let events = turn(&mut env, &conv, ask("read it")).await;
        let id = env.claude.lock().unwrap().session.id().to_string();
        assert!(matches!(&events[0], AiEvent::ClaudeSession { session_id, retired: None } if *session_id == id), "the chat learns the session before anything runs: {events:?}");
        assert!(events.iter().any(|e| matches!(e, AiEvent::Started { caption, fallback: false, .. } if caption == "cloud · Claude plan · Sonnet")));
        assert!(events.iter().any(|e| matches!(e, AiEvent::Engine(r) if r.model == "claude-sonnet-5-5")));
        let steps: Vec<String> = events.iter().filter_map(|e| if let AiEvent::Step(s) = e { Some(format!("{}:{:?}", s.id, s.state)) } else { None }).collect();
        assert_eq!(steps.last().map(String::as_str), Some("toolu_01B:Failed"));
        assert_eq!(done_text(&events).as_deref(), Some("I'll read the README.\n\nIt says it is a tiny demo."));
        assert_eq!(conv.lock().unwrap().turns.len(), 2);
        let again = env.claude.lock().unwrap().session.plan(&claude_code::Level::ChatOnly, "sonnet", &dir.path().join("chat").to_string_lossy(), Platform::Linux, || "x".into());
        assert!(again.turn.resume, "Claude Code made the session: the next turn resumes it");
        assert_eq!(fake_calls(&log).iter().filter(|c| c["argv"][0] == "-p").count(), 1);
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn a_level_change_that_moves_the_folder_starts_a_new_session_with_a_recap() {
        let dir = testkit::TempDir::new("claude-move");
        let _runs = testkit::claude_runs_shared();
        let (exe, log) = claude_script(&dir, &transcript("success.jsonl"), "claude");
        let mut env = claude_env(&dir, &exe);
        let conv = Mutex::new(Conversation::default());
        turn(&mut env, &conv, ask("first question")).await;
        let first = env.claude.lock().unwrap().session.id().to_string();
        let project = dir.path().join("project");
        std::fs::create_dir_all(&project).unwrap();
        env.claude.lock().unwrap().level = claude_code::Level::ReadOnly(project.to_string_lossy().to_string());
        let events = turn(&mut env, &conv, ask("second question")).await;
        assert!(matches!(&events[0], AiEvent::ClaudeSession { session_id, retired: Some(old) } if *old == first && *session_id != first), "the old id is retired: {events:?}");
        let calls: Vec<serde_json::Value> = fake_calls(&log).into_iter().filter(|c| c["argv"][0] == "-p").collect();
        assert_eq!(calls.len(), 2);
        let argv: Vec<&str> = calls[1]["argv"].as_array().unwrap().iter().map(|a| a.as_str().unwrap()).collect();
        assert!(argv.contains(&"--session-id") && !argv.contains(&"--resume"), "a new session, not a resume that could not find the old one");
        let stdin: serde_json::Value = serde_json::from_str(calls[1]["stdin"].as_str().unwrap()).unwrap();
        let texts: Vec<&str> = stdin["message"]["content"].as_array().unwrap().iter().map(|b| b["text"].as_str().unwrap()).collect();
        assert!(texts[0].starts_with("Earlier in this chat") && texts[0].contains("User: first question") && texts[1] == "second question", "{texts:?}");
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn a_new_session_that_failed_before_it_started_is_retried_with_its_recap() {
        let dir = testkit::TempDir::new("claude-recap-retry");
        let _runs = testkit::claude_runs_shared();
        let (good, _) = claude_script(&dir, &transcript("success.jsonl"), "good");
        let (signed_out, _) = claude_script(&dir, &transcript("signed-out.jsonl"), "signed-out");
        let (retry_exe, retry_log) = claude_script(&dir, &transcript("success.jsonl"), "retry");
        let mut env = claude_env(&dir, &good);
        let conv = Mutex::new(Conversation::default());
        turn(&mut env, &conv, ask("first question")).await;
        let project = dir.path().join("project");
        std::fs::create_dir_all(&project).unwrap();
        {
            let mut chat = env.claude.lock().unwrap();
            chat.level = claude_code::Level::ReadOnly(project.to_string_lossy().to_string());
            chat.status.executable = Some(signed_out);
        }
        let failed = turn(&mut env, &conv, ask("second question")).await;
        assert!(matches!(failed.last().unwrap(), AiEvent::Error { kind: ErrorKind::Auth, .. }), "{failed:?}");
        assert!(!failed.iter().any(|e| matches!(e, AiEvent::Engine(_))), "it never reached init");

        env.claude.lock().unwrap().status.executable = Some(retry_exe);
        let again = turn(&mut env, &conv, ask("second question")).await;
        assert!(matches!(&again[0], AiEvent::ClaudeSession { retired: None, .. }), "the old id was retired once, with the failed turn: {again:?}");
        let calls: Vec<serde_json::Value> = fake_calls(&retry_log).into_iter().filter(|c| c["argv"][0] == "-p").collect();
        assert_eq!(calls.len(), 1);
        let stdin: serde_json::Value = serde_json::from_str(calls[0]["stdin"].as_str().unwrap()).unwrap();
        let texts: Vec<&str> = stdin["message"]["content"].as_array().unwrap().iter().map(|b| b["text"].as_str().unwrap()).collect();
        assert!(texts[0].starts_with("Earlier in this chat") && texts[0].contains("User: first question") && texts[1] == "second question", "the retry still carries the recap: {texts:?}");
    }

    #[tokio::test]
    async fn a_turn_with_companion_text_sends_it_as_the_system_prompt() {
        let local = FakeServer::start(&[]);
        let mut env = env(&[], None, Some(&local));
        env.system = Some("COMPANION-TEXT".into());
        let conv = Mutex::new(Conversation::default());
        turn(&mut env, &conv, ask("hi")).await;
        let sent = env.sent.lock().unwrap().clone();
        assert_eq!(sent.first().map(String::as_str), Some("system: COMPANION-TEXT"), "{sent:?}");
        assert!(!sent.iter().any(|l| l.contains(WEB_LINE)), "a local model is not told it can search");
    }

    #[tokio::test]
    async fn a_search_provider_gets_the_web_line() {
        let cloud = FakeServer::start(&[]);
        let mut env = env(&["anthropic"], Some(&cloud), None);
        env.system = Some("COMPANION-TEXT".into());
        let conv = Mutex::new(Conversation::default());
        turn(&mut env, &conv, ask("hi")).await;
        let sent = env.sent.lock().unwrap().clone();
        assert!(sent[0].ends_with(&format!("\n\n{WEB_LINE}")) && sent[0].starts_with("system: COMPANION-TEXT"), "{sent:?}");
    }

    #[tokio::test]
    async fn no_companion_text_keeps_the_built_in_prompt() {
        let local = FakeServer::start(&[]);
        let mut env = env(&[], None, Some(&local));
        let conv = Mutex::new(Conversation::default());
        turn(&mut env, &conv, ask("hi")).await;
        let sent = env.sent.lock().unwrap().clone();
        assert_eq!(sent.first().map(String::as_str), Some(format!("system: {SYSTEM_PROMPT_PLAIN}").as_str()));
    }

    #[tokio::test]
    async fn the_companion_text_is_cut_to_its_limit_in_characters() {
        let local = FakeServer::start(&[]);
        let mut env = env(&[], None, Some(&local));
        env.system = Some("é".repeat(40_000));
        let conv = Mutex::new(Conversation::default());
        turn(&mut env, &conv, ask("hi")).await;
        let sent = env.sent.lock().unwrap().clone();
        assert_eq!(sent[0].chars().count(), "system: ".chars().count() + SYSTEM_MAX_CHARS);
    }

    #[tokio::test]
    async fn a_quick_turn_leaves_the_chat_conversation_untouched() {
        let local = FakeServer::start(&[]);
        // The chat: two turns, its own record of what it sent, and its own Claude Code session.
        let chat_turns = Mutex::new(Conversation { turns: vec![Turn::user("first".into(), vec![]), Turn::assistant("ok".into())], generation: 0 });
        let chat_sent = Arc::new(Mutex::new(vec!["system: CHAT".to_string()]));
        let mut base = env(&[], None, Some(&local));
        base.sent = chat_sent.clone();
        let chat_claude = base.claude.clone();
        let chat_session = chat_claude.lock().unwrap().session.id().to_string();

        // A quick action runs with its own system text, its own `sent` and a Claude session of its own.
        let mut quick = quick_env(base, "QUICK-TEXT", claude_cli::Status::not_installed());
        let quick_turns = Mutex::new(Conversation::default());
        let cancel = Notify::new();
        let mut events = Vec::new();
        run_turn(&mut quick, &quick_turns, ask("fix this"), &cancel, &mut |e| events.push(e)).await;

        assert!(done_text(&events).is_some(), "the quick turn answered: {events:?}");
        assert_eq!(chat_turns.lock().unwrap().turns.len(), 2, "the chat's conversation is as it was");
        assert_eq!(*chat_sent.lock().unwrap(), ["system: CHAT"], "the chat's 'What the AI saw last' is not overwritten");
        assert_eq!(quick.sent.lock().unwrap().first().map(String::as_str), Some("system: QUICK-TEXT"));
        assert!(!Arc::ptr_eq(&quick.claude, &chat_claude), "the quick turn has a Claude session of its own");
        assert_eq!(chat_claude.lock().unwrap().session.id(), chat_session, "the chat's session id is untouched");
        assert_eq!(quick.claude.lock().unwrap().level, claude_code::Level::NoTools, "a quick Claude turn has no tools");
    }

    /// The tools a fake run was started with: the value after its `--tools` flag.
    #[cfg(unix)]
    fn tools_of(call: &serde_json::Value) -> String {
        let argv = call["argv"].as_array().unwrap();
        let at = argv.iter().position(|a| a == "--tools").expect("a --tools flag");
        argv[at + 1].as_str().unwrap().to_string()
    }

    /// A chat in a project folder (Read only), with a transcript that has no tools in its `init`.
    #[cfg(unix)]
    fn held_chat_env(dir: &testkit::TempDir, exe: &str) -> Env {
        let env = claude_env(dir, exe);
        let project = dir.path().join("project");
        std::fs::create_dir_all(&project).unwrap();
        env.claude.lock().unwrap().level = claude_code::Level::ReadOnly(project.to_string_lossy().to_string());
        env
    }

    /// A quick Explain starts its chat at no tools, and the chat stays there: its next turn runs at no tools too, though its
    /// level is still Read only.
    #[cfg(unix)]
    #[tokio::test]
    async fn a_quick_explain_holds_the_chat_at_no_tools() {
        let dir = testkit::TempDir::new("claude-hold");
        let _runs = testkit::claude_runs_shared();
        let (exe, log) = claude_script(&dir, &transcript("no-tools.jsonl"), "claude");
        let mut env = held_chat_env(&dir, &exe);
        let conv = Mutex::new(Conversation::default());
        let explained = turn(&mut env, &conv, TurnRequest { quick: true, ..ask("explain this") }).await;
        assert!(done_text(&explained).is_some(), "{explained:?}");
        let next = turn(&mut env, &conv, ask("and this")).await;
        assert!(done_text(&next).is_some(), "{next:?}");
        {
            let chat = env.claude.lock().unwrap();
            assert!(chat.quick_hold, "the hold stays until a pick");
            assert!(matches!(chat.level, claude_code::Level::ReadOnly(_)), "the chat's level is untouched");
        }
        let calls: Vec<serde_json::Value> = fake_calls(&log).into_iter().filter(|c| c["argv"][0] == "-p").collect();
        assert_eq!(calls.len(), 2);
        assert!(calls.iter().all(|c| tools_of(c).is_empty()), "both turns run at no tools: {calls:?}");
    }

    /// Retry on a held chat answers at no tools too.
    #[cfg(unix)]
    #[tokio::test]
    async fn a_held_chat_retries_at_no_tools() {
        let dir = testkit::TempDir::new("claude-hold-retry");
        let _runs = testkit::claude_runs_shared();
        let (exe, log) = claude_script(&dir, &transcript("no-tools.jsonl"), "claude");
        let mut env = held_chat_env(&dir, &exe);
        let conv = Mutex::new(Conversation::default());
        turn(&mut env, &conv, TurnRequest { quick: true, ..ask("explain this") }).await;
        let retried = turn(&mut env, &conv, TurnRequest { regenerate: true, ..ask("") }).await;
        assert!(done_text(&retried).is_some(), "{retried:?}");
        let calls: Vec<serde_json::Value> = fake_calls(&log).into_iter().filter(|c| c["argv"][0] == "-p").collect();
        assert_eq!(calls.len(), 2);
        assert!(calls.iter().all(|c| tools_of(c).is_empty()), "the retry is at no tools: {calls:?}");
    }

    /// A quick Explain whose run is refused for its tools: Claude Code was killed right after `init`, so the chat's session is
    /// retired, and Try again plans a fresh one instead of `--session-id` on an id Claude Code may have recorded.
    #[cfg(unix)]
    #[tokio::test]
    async fn a_refused_run_retires_the_chats_session() {
        let dir = testkit::TempDir::new("claude-refused-retire");
        let _runs = testkit::claude_runs_shared();
        let (exe, _log) = claude_script(&dir, &transcript("no-tools-leaky.jsonl"), "claude");
        let mut env = held_chat_env(&dir, &exe);
        let conv = Mutex::new(Conversation::default());
        let first = env.claude.lock().unwrap().session.id().to_string();
        let events = turn(&mut env, &conv, TurnRequest { quick: true, ..ask("explain this") }).await;
        assert!(done_text(&events).is_none(), "{events:?}");
        let mut chat = env.claude.lock().unwrap();
        assert!(chat.quick_hold, "Try again stays at no tools");
        assert_ne!(chat.session.id(), first, "the refused session is not planned again");
        let again = chat.session.plan(&claude_code::Level::NoTools, "sonnet", "/chat", Platform::Linux, claude_chat::new_id);
        assert!(!again.turn.resume && again.needs_recap, "{again:?}");
    }

    /// Picking any level ends the hold: the next turn runs at the level picked, here Chat only (the level the control
    /// seemed to be at).
    #[cfg(unix)]
    #[tokio::test]
    async fn picking_any_level_ends_the_hold() {
        let dir = testkit::TempDir::new("claude-hold-pick");
        let _runs = testkit::claude_runs_shared();
        let (exe, log) = claude_script(&dir, &transcript("no-tools.jsonl"), "claude");
        let mut env = held_chat_env(&dir, &exe);
        let conv = Mutex::new(Conversation::default());
        turn(&mut env, &conv, TurnRequest { quick: true, ..ask("explain this") }).await;
        env.claude.lock().unwrap().set_level(claude_code::Level::ChatOnly);
        assert!(!env.claude.lock().unwrap().quick_hold, "the pick ended the hold");
        let next = turn(&mut env, &conv, ask("next")).await;
        assert!(done_text(&next).is_some(), "{next:?}");
        let calls: Vec<serde_json::Value> = fake_calls(&log).into_iter().filter(|c| c["argv"][0] == "-p").collect();
        assert_eq!(calls.len(), 2);
        assert!(tools_of(&calls[0]).is_empty(), "the held turn had no tools");
        assert!(!tools_of(&calls[1]).is_empty(), "the next turn has Chat only's tools: {calls:?}");
    }

    #[test]
    fn sent_lines_name_files_and_images_but_never_their_bodies() {
        let req = ChatRequest {
            model: "m".into(),
            system: "SYS".into(),
            messages: vec![
                Message {
                    role: Role::User,
                    parts: vec![
                        Part::Text("hi".into()),
                        Part::FileText { name: "a.txt".into(), text: "BODY".into() },
                        Part::Image { name: "p.png".into(), mime: "image/png".into(), base64: "AAA".into() },
                        Part::Pdf { name: "d.pdf".into(), base64: "QQ".into() },
                    ],
                },
                Message { role: Role::Assistant, parts: vec![Part::Text("ok".into())] },
            ],
            tools: vec![],
            response_format: None,
            max_tokens: 1,
        };
        assert_eq!(sent_lines(&req), ["system: SYS", "user: hi", "user: [file a.txt]", "user: [image]", "user: [file d.pdf]", "assistant: ok"]);
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn the_claude_preamble_carries_the_head_and_the_text_every_turn() {
        let dir = testkit::TempDir::new("claude-head");
        let _runs = testkit::claude_runs_shared();
        let (exe, log) = claude_script(&dir, &transcript("success.jsonl"), "claude");
        let mut env = claude_env(&dir, &exe);
        env.system = Some("COMPANION-TEXT".into());
        let conv = Mutex::new(Conversation::default());
        turn(&mut env, &conv, ask("first")).await;
        turn(&mut env, &conv, ask("second")).await;
        let calls: Vec<serde_json::Value> = fake_calls(&log).into_iter().filter(|c| c["argv"][0] == "-p").collect();
        assert_eq!(calls.len(), 2);
        for call in &calls {
            let stdin: serde_json::Value = serde_json::from_str(call["stdin"].as_str().unwrap()).unwrap();
            let texts: Vec<&str> = stdin["message"]["content"].as_array().unwrap().iter().map(|b| b["text"].as_str().unwrap()).collect();
            assert!(texts[0].starts_with(CLAUDE_HEAD) && texts[0].contains("COMPANION-TEXT"), "{texts:?}");
        }
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn a_loaded_conversation_seeds_the_next_claude_turn_with_its_recap() {
        let dir = testkit::TempDir::new("claude-load");
        let _runs = testkit::claude_runs_shared();
        let (exe, log) = claude_script(&dir, &transcript("success.jsonl"), "claude");
        let mut env = claude_env(&dir, &exe);
        env.system = Some("COMPANION-TEXT".into());
        let conv = Mutex::new(Conversation::default());
        conv.lock().unwrap().turns = loaded_turns(&[
            LoadTurn { role: "user".into(), text: "first question".into() },
            LoadTurn { role: "assistant".into(), text: "first answer".into() },
        ]);
        env.claude.lock().unwrap().session.reseed();
        turn(&mut env, &conv, ask("second question")).await;
        let calls: Vec<serde_json::Value> = fake_calls(&log).into_iter().filter(|c| c["argv"][0] == "-p").collect();
        assert_eq!(calls.len(), 1);
        let stdin: serde_json::Value = serde_json::from_str(calls[0]["stdin"].as_str().unwrap()).unwrap();
        let texts: Vec<&str> = stdin["message"]["content"].as_array().unwrap().iter().map(|b| b["text"].as_str().unwrap()).collect();
        assert!(texts[0].starts_with(CLAUDE_HEAD), "{texts:?}");
        let head = texts[0].find("Earlier in this chat").expect("the recap is in the preamble");
        assert!(texts[0].find(CLAUDE_HEAD).unwrap() < head && texts[0].contains("COMPANION-TEXT"), "{texts:?}");
        assert!(texts[0].contains("User: first question") && texts[0].contains("Assistant: first answer"), "{texts:?}");
        assert_eq!(texts.last().copied(), Some("second question"), "the new message is last");
    }

    #[test]
    fn loaded_turns_keeps_two_roles_and_cuts() {
        let mut raw = vec![LoadTurn { role: "system".into(), text: "no".into() }, LoadTurn { role: "user".into(), text: "".into() }];
        raw.push(LoadTurn { role: "user".into(), text: "é".repeat(100_001) });
        raw.push(LoadTurn { role: "assistant".into(), text: "kept".into() });
        let kept = loaded_turns(&raw);
        assert_eq!(kept.iter().map(|t| t.role).collect::<Vec<_>>(), [Role::User, Role::Assistant]);
        assert_eq!(kept[0].text.chars().count(), 100_000, "a long message is cut to 100,000 characters");
        assert_eq!(kept[1].text, "kept");
        let many: Vec<LoadTurn> = (0..1_500).map(|i| LoadTurn { role: "user".into(), text: format!("m{i}") }).collect();
        let last = loaded_turns(&many);
        assert_eq!((last.len(), last[0].text.as_str(), last[999].text.as_str()), (1_000, "m500", "m1499"), "the last 1,000 turns");
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn the_plan_limit_says_when_it_resets_and_never_falls_back() {
        let dir = testkit::TempDir::new("claude-limit");
        let _runs = testkit::claude_runs_shared();
        let (exe, _) = claude_script(&dir, &transcript("plan-limit.jsonl"), "claude");
        let local = FakeServer::start(&[]);
        let mut env = claude_env(&dir, &exe);
        env.servers = vec![running("ollama", &local.base, Placement::Local)];
        let conv = Mutex::new(Conversation::default());
        let events = turn(&mut env, &conv, ask("hi")).await;
        match events.last().unwrap() {
            AiEvent::Error { kind, message, resets_at, action, retry_after } => {
                assert_eq!((*kind, message.as_str(), *resets_at, action.is_none(), retry_after.is_none()), (ErrorKind::Billing, "Your Claude plan's limit was reached.", Some(1_791_301_500), true, true));
            }
            other => panic!("{other:?}"),
        }
        assert!(local.requests().is_empty(), "the local model must not be asked");
        assert!(conv.lock().unwrap().turns.is_empty(), "a failed message leaves no half turn");
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn steps_already_taken_are_never_handed_to_another_model() {
        let dir = testkit::TempDir::new("claude-steps");
        let _runs = testkit::claude_runs_shared();
        // A step starts, then the run dies with nothing said: a temporary failure, but the step stays done.
        let broken = dir.path().join("steps-then-crash.jsonl");
        std::fs::write(&broken, "{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"__SESSION_ID__\",\"model\":\"claude-sonnet-5-5\",\"apiKeySource\":\"none\"}\n{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"tool_use\",\"id\":\"t1\",\"name\":\"Bash\",\"input\":{}}}}\n").unwrap();
        let (exe, _) = claude_script(&dir, &broken.to_string_lossy(), "claude");
        let local = FakeServer::start(&[]);
        let mut env = claude_env(&dir, &exe);
        env.servers = vec![running("ollama", &local.base, Placement::Local)];
        let conv = Mutex::new(Conversation::default());
        let events = turn(&mut env, &conv, ask("run it")).await;
        assert!(matches!(events.last().unwrap(), AiEvent::Error { kind: ErrorKind::Server, message, .. } if message == "Claude stopped unexpectedly."), "{events:?}");
        assert!(local.requests().is_empty(), "Auto does not ask the local model after steps");
        assert!(!events.iter().any(|e| matches!(e, AiEvent::Notice { .. })), "and says nothing about falling back");
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn a_claude_that_is_not_installed_falls_back_like_any_cloud() {
        let dir = testkit::TempDir::new("claude-missing");
        let local = FakeServer::start(&["--persona", "ollama"]);
        let mut env = claude_env(&dir, "/nonexistent/claude");
        env.servers = vec![running("ollama", &local.base, Placement::Local)];
        let conv = Mutex::new(Conversation::default());
        let events = turn(&mut env, &conv, ask("hi")).await;
        assert!(events.iter().any(|e| matches!(e, AiEvent::Started { fallback: true, .. })), "temporary, nothing done: the local retry runs: {events:?}");
    }

    #[tokio::test]
    async fn auto_with_a_key_answers_from_the_cloud_and_streams() {
        let cloud = FakeServer::start(&[]);
        let mut env = env(&["anthropic"], Some(&cloud), None);
        let conv = Mutex::new(Conversation::default());
        let events = turn(&mut env, &conv, ask("hi")).await;
        assert!(matches!(&events[0], AiEvent::Started { caption, fallback: false, .. } if caption == "cloud · claude-sonnet-5-5"));
        assert!(events.iter().any(|e| matches!(e, AiEvent::Delta { .. })));
        assert!(events.iter().any(|e| matches!(e, AiEvent::Citation { url, .. } if url == "https://example.com/cats")));
        assert_eq!(done_text(&events).as_deref(), Some("Cats sleep a lot."));
        assert_eq!(conv.lock().unwrap().turns.len(), 2);
    }

    #[tokio::test]
    async fn busy_cloud_falls_back_to_local_once_with_the_spec_message() {
        let cloud = FakeServer::start(&["--fail", "429"]);
        let local = FakeServer::start(&[]);
        let mut env = env(&["anthropic"], Some(&cloud), Some(&local));
        let conv = Mutex::new(Conversation::default());
        let events = turn(&mut env, &conv, ask("hi")).await;
        assert!(events.contains(&AiEvent::Notice { text: "Claude's busy right now, so Llama answered instead.".into() }));
        assert!(events.iter().any(|e| matches!(e, AiEvent::Started { caption, fallback: true, .. } if caption == "local · llama3.2")));
        assert!(done_text(&events).unwrap().starts_with("## Answer"));
        assert_eq!(env.settings.last_used_local, Some(ModelRef { provider: "ollama".into(), model: "llama3.2".into() }));
    }

    #[tokio::test]
    async fn rejected_key_never_falls_back() {
        let cloud = FakeServer::start(&["--fail", "401"]);
        let local = FakeServer::start(&[]);
        let mut env = env(&["anthropic"], Some(&cloud), Some(&local));
        let conv = Mutex::new(Conversation::default());
        let events = turn(&mut env, &conv, ask("hi")).await;
        assert_eq!(
            events.last().unwrap(),
            &AiEvent::Error { kind: ErrorKind::Auth, message: "Your Anthropic key was rejected.".into(), action: Some(Action::OpenSettings), retry_after: None, resets_at: None }
        );
        assert!(local.requests().is_empty(), "the local model must not be asked");
        assert!(conv.lock().unwrap().turns.is_empty(), "a failed message leaves no half turn");
    }

    #[tokio::test]
    async fn busy_without_local_counts_down() {
        let cloud = FakeServer::start(&["--fail", "429"]);
        let mut env = env(&["anthropic"], Some(&cloud), None);
        let conv = Mutex::new(Conversation::default());
        let events = turn(&mut env, &conv, ask("hi")).await;
        assert!(matches!(events.last().unwrap(), AiEvent::Error { kind: ErrorKind::RateLimited, retry_after: Some(2), message, .. }
            if message == "Claude is busy. Trying again in 2 s."));
    }

    #[tokio::test]
    async fn billing_never_falls_back() {
        let cloud = FakeServer::start(&["--fail", "billing"]);
        let local = FakeServer::start(&[]);
        let mut env = env(&["openai"], Some(&cloud), Some(&local));
        let conv = Mutex::new(Conversation::default());
        let events = turn(&mut env, &conv, ask("hi")).await;
        assert!(matches!(events.last().unwrap(), AiEvent::Error { kind: ErrorKind::Billing, message, action: Some(Action::OpenBilling { .. }), .. }
            if message == "Your OpenAI credit ran out."));
    }

    /// The display `Env` only knows that a key exists (`None`): a turn built on it sends nothing,
    /// above all no empty bearer token.
    #[tokio::test]
    async fn a_key_that_was_not_read_is_never_sent_anywhere() {
        let cloud = FakeServer::start(&[]);
        let mut env = env(&[], Some(&cloud), None);
        env.keys.insert("anthropic".into(), None);
        env.keys.insert("openai".into(), None);
        let conv = Mutex::new(Conversation::default());
        for provider in ["anthropic", "openai"] {
            env.settings.preferred_cloud = provider.into();
            let events = turn(&mut env, &conv, ask("hi")).await;
            assert!(!events.iter().any(|e| matches!(e, AiEvent::Delta { .. })), "{events:?}");
        }
        assert!(cloud.requests().is_empty(), "{:?}", cloud.requests());
    }

    #[tokio::test]
    async fn no_key_and_nothing_local_is_the_empty_state() {
        let mut env = env(&[], None, None);
        let conv = Mutex::new(Conversation::default());
        assert_eq!(turn(&mut env, &conv, ask("hi")).await, vec![AiEvent::EmptyState]);
        assert!(conv.lock().unwrap().turns.is_empty());
    }

    #[tokio::test]
    async fn no_key_uses_the_local_model() {
        let local = FakeServer::start(&[]);
        let mut env = env(&[], None, Some(&local));
        let conv = Mutex::new(Conversation::default());
        let events = turn(&mut env, &conv, ask("hi")).await;
        assert!(matches!(&events[0], AiEvent::Started { placement: Placement::Local, .. }));
        assert!(done_text(&events).is_some());
    }

    #[tokio::test]
    async fn explicit_local_choice_beats_a_cloud_key() {
        let cloud = FakeServer::start(&[]);
        let local = FakeServer::start(&[]);
        let mut env = env(&["anthropic"], Some(&cloud), Some(&local));
        env.settings.chat = Choice::Explicit(ModelRef { provider: "ollama".into(), model: "llama3.2".into() });
        let conv = Mutex::new(Conversation::default());
        let events = turn(&mut env, &conv, ask("hi")).await;
        assert!(matches!(&events[0], AiEvent::Started { provider, .. } if provider == "ollama"));
        assert!(cloud.requests().is_empty());
    }

    #[tokio::test]
    async fn a_cut_stream_keeps_the_partial_reply() {
        let local = FakeServer::start(&["--fail", "cut"]);
        let mut env = env(&[], None, Some(&local));
        let conv = Mutex::new(Conversation::default());
        let events = turn(&mut env, &conv, ask("hi")).await;
        assert_eq!(
            events.last().unwrap(),
            &AiEvent::Done { text: "Hello from ".into(), interrupted: true, cancelled: false }
        );
        // The partial reply stays in the history, so "Continue" makes sense.
        assert_eq!(conv.lock().unwrap().turns[1].text, "Hello from ");
    }

    #[tokio::test]
    async fn a_stream_cut_before_any_text_is_a_plain_failure() {
        // The cut Anthropic stream stops before its first text delta.
        let cloud = FakeServer::start(&["--fail", "cut"]);
        let mut env = env(&["anthropic"], Some(&cloud), None);
        let conv = Mutex::new(Conversation::default());
        let events = turn(&mut env, &conv, ask("hi")).await;
        assert!(matches!(events.last().unwrap(), AiEvent::Error { kind: ErrorKind::Server, message, .. }
            if message == "Claude had a problem. Try again in a moment."));
    }

    #[tokio::test]
    async fn stop_cancels_the_stream() {
        let local = FakeServer::start(&["--fail", "slow-first-token", "--delay", "3"]);
        let mut env = env(&[], None, Some(&local));
        let conv = Mutex::new(Conversation::default());
        let cancel = std::sync::Arc::new(Notify::new());
        let stopper = cancel.clone();
        tokio::spawn(async move {
            tokio::time::sleep(std::time::Duration::from_millis(300)).await;
            stopper.notify_one();
        });
        let mut events = Vec::new();
        let started = std::time::Instant::now();
        run_turn(&mut env, &conv, ask("hi"), &cancel, &mut |e| events.push(e)).await;
        assert!(started.elapsed() < std::time::Duration::from_secs(2));
        assert!(matches!(events.last().unwrap(), AiEvent::Done { cancelled: true, .. }));
        assert!(conv.lock().unwrap().turns.is_empty());
    }

    #[tokio::test]
    async fn a_file_joins_the_message_it_was_dropped_on() {
        // Regression: files used to ride along with a conversation's first message only.
        let local = FakeServer::start(&[]);
        let files = testkit::make_attachments();
        let mut env = env(&[], None, Some(&local));
        let conv = Mutex::new(Conversation::default());
        turn(&mut env, &conv, ask("hello")).await;
        let second = TurnRequest {
            feature: Feature::Files,
            text: "what does it say?".into(),
            files: vec![FileRef { name: "note.txt".into(), path: files.path().join("note.txt") }],
            regenerate: false,
            quick: false,
        };
        turn(&mut env, &conv, second).await;
        let chats: Vec<_> = local.requests().into_iter().filter(|r| r["path"] == "/v1/chat/completions").collect();
        let messages = chats[1]["body"]["messages"].as_array().unwrap();
        let last = messages.last().unwrap()["content"].as_str().unwrap();
        assert!(last.contains("Hello Shrimpy") && last.contains("what does it say?"), "{last}");
        assert!(!messages[1]["content"].as_str().unwrap().contains("Hello Shrimpy"));
    }

    #[tokio::test]
    async fn a_follow_up_to_a_file_stays_on_the_file_questions_model() {
        // The webview says Chat, but a file is in the conversation: Rust holds the line.
        let cloud = FakeServer::start(&[]);
        let local = FakeServer::start(&[]);
        let files = testkit::make_attachments();
        let mut env = env(&["anthropic"], Some(&cloud), Some(&local));
        env.settings.chat = Choice::Explicit(ModelRef { provider: "anthropic".into(), model: "claude-opus-5".into() });
        env.settings.files = Choice::Explicit(ModelRef { provider: "ollama".into(), model: "llama3.2".into() });
        let conv = Mutex::new(Conversation::default());
        let first = TurnRequest {
            feature: Feature::Files,
            text: "what does it say?".into(),
            files: vec![FileRef { name: "note.txt".into(), path: files.path().join("note.txt") }],
            regenerate: false,
            quick: false,
        };
        turn(&mut env, &conv, first).await;
        turn(&mut env, &conv, ask("and then?")).await;
        let chats = local.requests().into_iter().filter(|r| r["path"] == "/v1/chat/completions").count();
        assert_eq!(chats, 2, "the follow-up went to the File questions model");
        assert!(cloud.requests().is_empty(), "the file's text must not reach the Chat model");
    }

    #[tokio::test]
    async fn retry_answers_the_last_message_again() {
        let local = FakeServer::start(&[]);
        let mut env = env(&[], None, Some(&local));
        let conv = Mutex::new(Conversation::default());
        turn(&mut env, &conv, ask("hi")).await;
        let events = turn(&mut env, &conv, TurnRequest { regenerate: true, ..ask("") }).await;
        assert!(done_text(&events).is_some());
        let c = conv.lock().unwrap();
        assert_eq!(c.turns.len(), 2);
        assert_eq!(c.turns[0].text, "hi");
    }

    #[tokio::test]
    async fn a_blind_model_and_an_image_say_so() {
        let local = FakeServer::start(&[]);
        let files = testkit::make_attachments();
        let mut env = env(&[], None, Some(&local));
        let conv = Mutex::new(Conversation::default());
        let req = TurnRequest {
            feature: Feature::Files,
            text: "what is it?".into(),
            files: vec![FileRef { name: "photo.png".into(), path: files.path().join("photo.png") }],
            regenerate: false,
            quick: false,
        };
        let events = turn(&mut env, &conv, req).await;
        if cfg!(windows) {
            // Windows reads the (blank) image with OCR, finds nothing, and says the same.
            assert!(matches!(events.last().unwrap(), AiEvent::Problem { kind: ProblemKind::CantSee, .. }));
        } else {
            assert_eq!(
                events.last().unwrap(),
                &AiEvent::Problem { kind: ProblemKind::CantSee, message: errors::CANT_SEE.into(), action: Some(Action::ChooseModel) }
            );
        }
    }

    #[tokio::test]
    async fn prompts_and_files_never_reach_the_log() {
        const MARKER: &str = "QUOKKAMARKER7731";
        let dir = testkit::TempDir::new("leak");
        let file = dir.path().join("secret.txt");
        std::fs::write(&file, format!("the password is {MARKER}\n")).unwrap();
        let ok = FakeServer::start(&[]);
        let failing = FakeServer::start(&["--fail", "500"]);
        for cloud in [&ok, &failing] {
            let mut env = env(&["anthropic"], Some(cloud), None);
            let conv = Mutex::new(Conversation::default());
            let req = TurnRequest {
                feature: Feature::Files,
                text: format!("tell me about {MARKER}"),
                files: vec![FileRef { name: format!("{MARKER}.txt"), path: file.clone() }],
                regenerate: false,
                quick: false,
            };
            turn(&mut env, &conv, req).await;
        }
        let lines = log::CAPTURED.lock().unwrap().clone();
        assert!(lines.iter().any(|l| l.starts_with("ai ")), "the turns were logged");
        assert!(lines.iter().all(|l| !l.contains(MARKER)), "a prompt or file leaked into the log");
    }

    #[tokio::test]
    async fn a_server_that_quit_after_discovery_is_reported_and_forgotten() {
        let port = std::net::TcpListener::bind("127.0.0.1:0").unwrap().local_addr().unwrap().port();
        let gone = format!("http://127.0.0.1:{port}");
        let mut env = env(&[], None, None);
        env.servers = vec![running("ollama", &gone, Placement::Local)];
        let conv = Mutex::new(Conversation::default());
        let events = turn(&mut env, &conv, ask("hi")).await;
        // A closed port is refused at once on Linux and macOS; Windows can retry the connection and report a timeout instead,
        // and only a refused connection forgets the server. Either way the turn failed.
        if cfg!(windows) {
            assert!(matches!(events.last().unwrap(), AiEvent::Error { kind: ErrorKind::Unreachable | ErrorKind::Timeout, .. }), "{events:?}");
            return;
        }
        assert_eq!(
            events.last().unwrap(),
            &AiEvent::Error {
                kind: ErrorKind::Unreachable,
                message: "Couldn't reach Ollama. Is its server on?".into(),
                action: Some(Action::OpenGuide),
                retry_after: None,
                resets_at: None,
            }
        );
        assert_eq!(env.servers[0].status, ServerStatus::Off, "the next message looks again");
    }

    #[tokio::test]
    async fn a_reply_to_a_reset_conversation_is_dropped() {
        let local = FakeServer::start(&["--fail", "slow-first-token", "--delay", "1"]);
        let mut env = env(&[], None, Some(&local));
        let conv = Mutex::new(Conversation::default());
        let cancel = Notify::new();
        let mut events = Vec::new();
        let mut emit = |e| events.push(e);
        let run = run_turn(&mut env, &conv, ask("old question"), &cancel, &mut emit);
        let reset = async {
            tokio::time::sleep(std::time::Duration::from_millis(300)).await;
            conv.lock().unwrap().reset();
        };
        tokio::join!(run, reset);
        assert!(conv.lock().unwrap().turns.is_empty(), "the old reply must not land in the new conversation");
    }

    #[tokio::test]
    async fn stale_explicit_choices_say_what_happened() {
        let local = FakeServer::start(&[]);
        let mut env = env(&[], None, Some(&local));
        env.settings.chat = Choice::Explicit(ModelRef { provider: "anthropic".into(), model: "claude-opus-5".into() });
        let conv = Mutex::new(Conversation::default());
        let events = turn(&mut env, &conv, ask("hi")).await;
        assert!(matches!(events.last().unwrap(), AiEvent::Error { message, action: Some(Action::OpenSettings), .. }
            if message == "Your Anthropic key is missing."));

        env.settings.chat = Choice::Explicit(ModelRef { provider: "ollama".into(), model: "qwen3.5:2b".into() });
        let events = turn(&mut env, &conv, ask("hi")).await;
        assert!(matches!(events.last().unwrap(), AiEvent::Problem { kind: ProblemKind::MissingModel, message, action: Some(Action::ChooseModel) }
            if message == "qwen3.5:2b isn't on Ollama any more."));
        assert!(local.requests().iter().all(|r| r["path"] != "/v1/chat/completions"), "no other model answered instead");
    }

    #[tokio::test]
    async fn a_thinking_model_that_runs_out_of_tokens_says_so_and_adds_no_turn() {
        // Every token went into <think>: the visible reply is empty and the model stopped at the limit.
        let mut env = canned_reply(&["<think>\nlet me weigh this ", "for a very long time"], "length");
        let conv = Mutex::new(Conversation::default());
        let events = turn(&mut env, &conv, ask("hi")).await;
        assert!(!events.iter().any(|e| matches!(e, AiEvent::Done { .. })), "no Done, so no finish sound: {events:?}");
        assert!(!events.iter().any(|e| matches!(e, AiEvent::Delta { .. })), "the thinking is never shown");
        assert_eq!(
            events.last().unwrap(),
            &AiEvent::Problem {
                kind: ProblemKind::EmptyReply,
                message: "The model ran out of room before answering. Try again, or pick a model without thinking mode.".into(),
                action: Some(Action::ChooseModel),
            }
        );
        assert!(conv.lock().unwrap().turns.is_empty(), "no empty assistant turn, and the question is taken back");
    }

    #[tokio::test]
    async fn a_reply_cut_off_at_the_token_limit_is_kept_with_a_note() {
        let mut env = canned_reply(&["The first half of an ans"], "length");
        let conv = Mutex::new(Conversation::default());
        let events = turn(&mut env, &conv, ask("hi")).await;
        let note = events.iter().position(|e| *e == AiEvent::Notice { text: "The answer was cut off.".into() });
        let done = events.iter().position(|e| matches!(e, AiEvent::Done { .. }));
        assert!(note.is_some() && note < done, "the note comes before Done: {events:?}");
        assert_eq!(
            events.last().unwrap(),
            &AiEvent::Done { text: "The first half of an ans".into(), interrupted: false, cancelled: false }
        );
        assert_eq!(conv.lock().unwrap().turns[1].text, "The first half of an ans");
    }

    #[tokio::test]
    async fn an_unclosed_think_block_never_becomes_the_reply() {
        let mut env = canned_reply(&["Sure. <think>hm"], "length");
        let conv = Mutex::new(Conversation::default());
        let events = turn(&mut env, &conv, ask("hi")).await;
        assert_eq!(done_text(&events).as_deref(), Some("Sure. "));
        assert_eq!(conv.lock().unwrap().turns[1].text, "Sure. ");
    }

    #[tokio::test]
    async fn an_empty_reply_is_a_failure_whatever_the_finish() {
        for deltas in [&[][..], &["  \n"][..]] {
            let mut env = canned_reply(deltas, "stop");
            let conv = Mutex::new(Conversation::default());
            let events = turn(&mut env, &conv, ask("hi")).await;
            assert_eq!(
                events.last().unwrap(),
                &AiEvent::Problem {
                    kind: ProblemKind::EmptyReply,
                    message: "The model sent an empty reply. Try again.".into(),
                    action: None,
                },
                "{deltas:?}"
            );
            assert!(!events.iter().any(|e| matches!(e, AiEvent::Done { .. })));
            assert!(conv.lock().unwrap().turns.is_empty());
        }
    }

    /// A cloud answer that says no and carries no words, with a local model ready. The refusal
    /// is told to the person and never retried on another model, whether or not the stream ended.
    #[tokio::test]
    async fn an_empty_refusal_is_a_refusal_and_never_a_local_retry() {
        let anthropic = |events: &[&str]| ("anthropic", events.iter().map(|e| format!("data: {e}\n\n")).collect::<String>());
        let refusal = |events: &[&str]| ("openai", events.iter().map(|e| format!("data: {e}\n\n")).collect::<String>());
        let cases = [
            ("anthropic, stop_reason refusal, no text", anthropic(&[
                r#"{"type":"message_delta","delta":{"stop_reason":"refusal"}}"#, r#"{"type":"message_stop"}"#])),
            ("anthropic, refusal then the stream is cut", anthropic(&[
                r#"{"type":"message_delta","delta":{"stop_reason":"refusal"}}"#])),
            ("openai, empty refusal", refusal(&[
                r#"{"type":"response.refusal.done","refusal":""}"#, r#"{"type":"response.completed"}"#])),
            ("openai, empty refusal then the stream is cut", refusal(&[
                r#"{"type":"response.refusal.done","refusal":""}"#])),
        ];
        for (name, (provider, body)) in cases {
            let cloud = testkit::canned_server(200, "text/event-stream", &body);
            let local = FakeServer::start(&[]);
            let mut env = env(&[provider], None, Some(&local));
            env.cloud_override = Some(cloud);
            let conv = Mutex::new(Conversation::default());
            let events = turn(&mut env, &conv, ask("hi")).await;
            assert!(matches!(events.last().unwrap(), AiEvent::Error { kind: ErrorKind::Refusal, message, .. } if !message.is_empty()), "{name}: {events:?}");
            assert!(!events.iter().any(|e| matches!(e, AiEvent::Notice { .. } | AiEvent::Done { .. })), "{name}: {events:?}");
            assert!(local.requests().iter().all(|r| r["path"] != "/v1/chat/completions"), "{name}: the local model must not be asked");
            assert!(conv.lock().unwrap().turns.is_empty(), "{name}");
        }
    }

    fn ollama_probe(base: &str) -> Probe {
        Probe { provider: "ollama".into(), base_url: base.into(), key: None }
    }

    #[tokio::test]
    async fn auto_rescans_once_for_a_local_server_after_a_busy_cloud() {
        // Ollama was started after the last scan: no local server is known when the cloud says "overloaded".
        let cloud = FakeServer::start(&["--fail", "overloaded"]);
        let local = FakeServer::start(&["--persona", "ollama"]);
        let mut env = env(&["anthropic"], Some(&cloud), None);
        env.probes = vec![ollama_probe(&local.base)];
        assert!(env.servers.is_empty());
        let conv = Mutex::new(Conversation::default());
        let events = turn(&mut env, &conv, ask("hi")).await;
        assert!(events.iter().any(|e| matches!(e, AiEvent::Started { fallback: true, provider, .. } if provider == "ollama")), "{events:?}");
        assert!(done_text(&events).is_some(), "{events:?}");
        let scans = local.requests().iter().filter(|r| r["path"] == "/api/version").count();
        assert_eq!(scans, 1, "one scan for the whole message");
    }

    #[tokio::test]
    async fn the_rescan_asks_only_localhost_and_leaves_a_slow_server_as_it_was() {
        // A server the user added on another network answers slowly; the 0.3 s localhost scan must neither
        // wait for it nor flip it to "off".
        let local = FakeServer::start(&["--persona", "ollama"]);
        let far = "http://192.0.2.1:1234";
        let (host, placement, unencrypted) = discovery::describe("custom", far);
        let mut env = env(&[], None, None);
        env.probes = vec![ollama_probe(&local.base), Probe { provider: "custom".into(), base_url: far.into(), key: None }];
        env.servers = vec![Server {
            provider: "custom".into(),
            name: host.clone(),
            base_url: far.into(),
            host,
            placement,
            status: ServerStatus::Running,
            models: vec![ModelInfo::named("gemma")],
            unencrypted,
        }];
        let started = std::time::Instant::now();
        env.rediscover(None).await;
        assert!(started.elapsed() < std::time::Duration::from_millis(250), "{:?}", started.elapsed());
        let status = |p: &str| env.servers.iter().find(|s| s.provider == p).map(|s| s.status);
        assert_eq!(status("ollama"), Some(ServerStatus::Running));
        assert_eq!(status("custom"), Some(ServerStatus::Running), "not probed, so not flipped to off");
    }

    #[tokio::test]
    async fn an_explicit_choice_of_the_added_server_finds_it_again_after_a_stale_off() {
        // The last scan saw the added server off; it is up now, but sleepy (its model list takes 1 s, which the
        // 0.3 s localhost scan would call "off"). An explicit turn to it probes it again with the added-server limit.
        let lan = FakeServer::start(&["--fail", "slow-models", "--delay", "1"]);
        let mut env = env(&[], None, None);
        env.probes = vec![Probe { provider: "custom".into(), base_url: lan.base.clone(), key: None }];
        let mut stale = running("custom", &lan.base, Placement::Network);
        (stale.status, stale.models) = (ServerStatus::Off, Vec::new());
        env.servers = vec![stale];
        env.settings.chat = Choice::Explicit(ModelRef { provider: "custom".into(), model: "llama3.2".into() });
        let conv = Mutex::new(Conversation::default());
        let events = turn(&mut env, &conv, ask("hi")).await;
        assert!(events.iter().any(|e| matches!(e, AiEvent::Started { provider, .. } if provider == "custom")), "{events:?}");
        assert!(done_text(&events).is_some(), "{events:?}");
        assert_eq!(env.servers[0].status, ServerStatus::Running);
    }

    /// The history budget follows the context the server reports for the model, not a flat 4,096.
    #[tokio::test]
    async fn the_history_budget_uses_the_context_the_server_reports() {
        // Two 6,000-character turns plus a question: too long for 4,096 tokens, fine for 8,192.
        let dropped = |persona: &'static str, provider: &'static str, model: &'static str| async move {
            let local = FakeServer::start(&["--persona", persona]);
            let mut env = env(&[], None, None);
            let mut server = running(provider, &local.base, Placement::Local);
            server.models = vec![ModelInfo::named(model)];
            env.servers = vec![server];
            let conv = Mutex::new(Conversation::default());
            conv.lock().unwrap().turns = vec![Turn::user("a".repeat(6000), vec![]), Turn::assistant("b".repeat(6000))];
            let events = turn(&mut env, &conv, ask("and now?")).await;
            assert!(events.iter().any(|e| matches!(e, AiEvent::Started { .. })), "{events:?}");
            events.contains(&AiEvent::Notice { text: errors::TOO_LONG.into() })
        };
        assert!(!dropped("ollama-ctx", "ollama", "ctx-runtime").await, "Ollama runs it at num_ctx 8192");
        assert!(dropped("ollama-ctx", "ollama", "ctx-trained-big").await, "trained 131072, capped at 4096");
        assert!(dropped("ollama-ctx", "ollama", "ctx-trained-small").await, "2048 is smaller still");
        assert!(dropped("ollama-ctx", "ollama", "ctx-none").await, "nothing reported counts 4096");
        assert!(!dropped("lmstudio-ctx", "lmstudio", "lm-loaded").await, "LM Studio loaded it at 16384");
        assert!(dropped("lmstudio-ctx", "lmstudio", "lm-max-big").await, "not loaded: the trained maximum, capped");
        assert!(dropped("lmstudio-ctx", "lmstudio", "lm-zero").await, "0 is unknown");
    }

    /// `maxOutputTokens` for a placement, read from providers.json.
    fn reply_length(placement: &str) -> serde_json::Value {
        testkit::load_json("providers.json")["maxOutputTokens"][placement].clone()
    }

    #[tokio::test]
    async fn every_request_asks_for_its_placements_reply_length() {
        // A thinking model spends its <think> or reasoning tokens from this cap.
        let local = FakeServer::start(&[]);
        let mut at_home = env(&[], None, Some(&local));
        turn(&mut at_home, &Mutex::new(Conversation::default()), ask("hi")).await;
        let chat = local.requests().into_iter().find(|r| r["path"] == "/v1/chat/completions").unwrap();
        assert_eq!(chat["body"]["max_tokens"], reply_length("local"));

        let cloud = FakeServer::start(&[]);
        let mut away = env(&["anthropic", "openai"], Some(&cloud), None);
        turn(&mut away, &Mutex::new(Conversation::default()), ask("hi")).await;
        away.settings.preferred_cloud = "openai".into();
        turn(&mut away, &Mutex::new(Conversation::default()), ask("hi")).await;
        let log = cloud.requests();
        assert_eq!(log.iter().find(|r| r["path"] == "/v1/messages").unwrap()["body"]["max_tokens"], reply_length("cloud"));
        assert_eq!(log.iter().find(|r| r["path"] == "/v1/responses").unwrap()["body"]["max_output_tokens"], reply_length("cloud"));
        // A server on the network gets the local length.
        away.servers = vec![running("custom", &local.base, Placement::Network)];
        away.keys.clear();
        let events = turn(&mut away, &Mutex::new(Conversation::default()), ask("hi again")).await;
        assert!(events.iter().any(|e| matches!(e, AiEvent::Started { placement: Placement::Network, .. })), "{events:?}");
        let last = local.requests().into_iter().filter(|r| r["path"] == "/v1/chat/completions").last().unwrap();
        assert_eq!(last["body"]["max_tokens"], reply_length("network"));
    }

    #[tokio::test]
    async fn a_long_chat_on_a_small_model_drops_the_oldest_pair_and_says_so() {
        let local = FakeServer::start(&[]);
        let mut at_home = env(&[], None, Some(&local));
        let conv = Mutex::new(Conversation::default());
        conv.lock().unwrap().turns = vec![Turn::user("a".repeat(6000), vec![]), Turn::assistant("b".repeat(6000))];
        let events = turn(&mut at_home, &conv, ask("and now?")).await;
        // An unknown local context counts as 4,096 tokens: 10,752 scalars fit, and 12,000+ do not.
        assert!(events.contains(&AiEvent::Notice { text: errors::TOO_LONG.into() }), "{events:?}");
        let chat = local.requests().into_iter().find(|r| r["path"] == "/v1/chat/completions").unwrap();
        let sent = chat["body"]["messages"].as_array().unwrap();
        assert_eq!(sent.len(), 2, "the system prompt and the latest message only");
        assert_eq!(sent[1]["content"], "and now?");
        // The conversation itself keeps every turn: only what is sent was trimmed.
        assert_eq!(conv.lock().unwrap().turns.len(), 4);
    }

    #[tokio::test]
    async fn a_failed_retry_keeps_the_question_it_retries() {
        let local = FakeServer::start(&[]);
        let mut env = env(&[], None, Some(&local));
        let conv = Mutex::new(Conversation::default());
        turn(&mut env, &conv, ask("hi")).await;
        // The server goes away, so the retry fails. It pushed no message, so it must not take one back.
        let port = std::net::TcpListener::bind("127.0.0.1:0").unwrap().local_addr().unwrap().port();
        env.servers[0].base_url = format!("http://127.0.0.1:{port}");
        let events = turn(&mut env, &conv, TurnRequest { regenerate: true, ..ask("") }).await;
        // A closed port is refused at once on Linux and macOS; Windows retries the connection and reports a timeout instead. Either way the retry failed.
        assert!(matches!(events.last().unwrap(), AiEvent::Error { kind: ErrorKind::Unreachable | ErrorKind::Timeout, .. }), "{events:?}");
        let c = conv.lock().unwrap();
        assert_eq!(c.turns.len(), 1, "the old reply went when Retry was pressed; the question stays");
        assert_eq!(c.turns[0].text, "hi");
    }

    #[tokio::test]
    async fn later_messages_reuse_what_was_prepared_for_a_file() {
        let local = FakeServer::start(&[]);
        let dir = testkit::TempDir::new("reuse");
        let file = dir.path().join("memo.txt");
        std::fs::write(&file, "the memo says QUOKKA\n").unwrap();
        let mut env = env(&[], None, Some(&local));
        let conv = Mutex::new(Conversation::default());
        let first = TurnRequest {
            feature: Feature::Files,
            text: "what does it say?".into(),
            files: vec![FileRef { name: "memo.txt".into(), path: file.clone() }],
            regenerate: false,
            quick: false,
        };
        turn(&mut env, &conv, first).await;
        assert_eq!(conv.lock().unwrap().turns[0].prepared.len(), 1, "prepared once, on the message it was dropped on");

        // The inbox sweep removes the file; the conversation goes on.
        std::fs::remove_file(&file).unwrap();
        let events = turn(&mut env, &conv, ask("and then?")).await;
        assert!(done_text(&events).is_some(), "{events:?}");
        let chats: Vec<_> = local.requests().into_iter().filter(|r| r["path"] == "/v1/chat/completions").collect();
        let earlier = chats[1]["body"]["messages"][1]["content"].as_str().unwrap();
        assert!(earlier.contains("the memo says QUOKKA"), "{earlier}");
        assert_eq!(conv.lock().unwrap().turns[0].prepared.len(), 1, "and not prepared again");
    }

    #[tokio::test]
    async fn an_earlier_file_that_is_gone_does_not_block_a_new_question() {
        let local = FakeServer::start(&[]);
        let mut env = env(&[], None, Some(&local));
        let conv = Mutex::new(Conversation::default());
        {
            let mut c = conv.lock().unwrap();
            let gone = FileRef { name: "gone.txt".into(), path: PathBuf::from("/definitely/not/here/gone.txt") };
            c.turns.push(Turn::user("what is it?".into(), vec![gone]));
            c.turns.push(Turn::assistant("A memo.".into()));
        }
        let events = turn(&mut env, &conv, ask("thanks, and?")).await;
        assert!(done_text(&events).is_some(), "{events:?}");
        let chats: Vec<_> = local.requests().into_iter().filter(|r| r["path"] == "/v1/chat/completions").collect();
        let earlier = chats[0]["body"]["messages"][1]["content"].as_str().unwrap();
        assert!(earlier.contains("File: gone.txt (no longer available)"), "{earlier}");
        assert!(conv.lock().unwrap().turns[0].prepared.is_empty(), "a miss is not cached: a later message tries again");

        // The newest message's own file is different: a file that can't be read is said so.
        let missing_now = TurnRequest {
            feature: Feature::Files,
            text: "read this".into(),
            files: vec![FileRef { name: "new.txt".into(), path: PathBuf::from("/definitely/not/here/new.txt") }],
            regenerate: false,
            quick: false,
        };
        let events = turn(&mut env, &conv, missing_now).await;
        assert!(matches!(events.last().unwrap(), AiEvent::Problem { kind: ProblemKind::Unreadable, .. }), "{events:?}");
    }

    #[tokio::test]
    async fn files_nothing_here_can_read_say_why_not_that_the_model_cannot_see() {
        let local = FakeServer::start(&[]);
        let files = testkit::make_attachments();
        let heic = files.path().join("IMG_0001.HEIC");
        std::fs::write(&heic, b"\0\0\0\x18ftypheic").unwrap();
        let mut env = env(&[], None, Some(&local));
        let conv = Mutex::new(Conversation::default());
        let about = |name: &str, path: PathBuf| TurnRequest {
            feature: Feature::Files,
            text: "what is it?".into(),
            files: vec![FileRef { name: name.into(), path }],
            regenerate: false,
            quick: false,
        };
        let events = turn(&mut env, &conv, about("scan.pdf", files.path().join("scan.pdf"))).await;
        assert_eq!(
            events.last().unwrap(),
            &AiEvent::Problem { kind: ProblemKind::ScannedPdf, message: errors::scanned_pdf_copy().into(), action: None }
        );
        let events = turn(&mut env, &conv, about("IMG_0001.HEIC", heic)).await;
        assert_eq!(
            events.last().unwrap(),
            &AiEvent::Problem { kind: ProblemKind::Heic, message: errors::HEIC.into(), action: None }
        );
        assert!(conv.lock().unwrap().turns.is_empty());
    }

    #[test]
    fn island_notices_are_not_contract_error_kinds() {
        let contract = [
            ErrorKind::Offline, ErrorKind::Unreachable, ErrorKind::Timeout, ErrorKind::Server,
            ErrorKind::RateLimited, ErrorKind::Overloaded, ErrorKind::Auth, ErrorKind::BadRequest,
            ErrorKind::Billing, ErrorKind::Refusal, ErrorKind::Cancelled, ErrorKind::Interrupted,
        ];
        let names: Vec<&str> = contract.iter().map(|k| k.as_str()).collect();
        for kind in [
            ProblemKind::CantSee, ProblemKind::ScannedPdf, ProblemKind::Heic, ProblemKind::Rejected,
            ProblemKind::Unreadable, ProblemKind::MissingModel, ProblemKind::Outdated, ProblemKind::EmptyReply,
        ] {
            let name = serde_json::to_value(kind).unwrap();
            assert!(!names.contains(&name.as_str().unwrap()), "{name} is a contract kind");
        }
        // And on the wire they differ by event type: `problem`, never `error`.
        let event = AiEvent::Problem { kind: ProblemKind::CantSee, message: "x".into(), action: None };
        assert_eq!(serde_json::to_value(event).unwrap(), serde_json::json!({ "type": "problem", "kind": "cant_see", "message": "x", "action": null }));
        let event = AiEvent::Error { kind: ErrorKind::RateLimited, message: "x".into(), action: None, retry_after: Some(2), resets_at: None };
        assert_eq!(
            serde_json::to_value(event).unwrap(),
            serde_json::json!({ "type": "error", "kind": "rate_limited", "message": "x", "action": null, "retryAfter": 2 })
        );
    }

    #[test]
    fn resolve_describes_auto_and_its_fallback() {
        let mut env = env(&["anthropic"], None, None);
        env.servers = vec![running("ollama", "http://127.0.0.1:11434", Placement::Local)];
        env.models.insert(
            "anthropic".into(),
            vec![ModelInfo {
                id: "claude-sonnet-5-5".into(),
                display_name: "Claude Sonnet 5.5".into(),
                context_tokens: None,
                capabilities: Capabilities::default(),
            }],
        );
        let r = resolve(&env, Feature::Chat);
        assert_eq!(r.reader.as_deref(), Some("Claude"));
        assert_eq!(r.model_name.as_deref(), Some("Claude Sonnet 5.5"));
        assert_eq!(r.fallback.as_deref(), Some("Local · llama3.2"));
        env.keys.clear();
        env.servers.clear();
        assert!(resolve(&env, Feature::Files).empty);
    }
}
