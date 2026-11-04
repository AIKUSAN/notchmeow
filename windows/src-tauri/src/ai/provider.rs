// The types every model provider speaks. They mirror the shared contract in
// tests/fixtures/ai/ and docs/AI-PROVIDERS.md, so the names match the macOS app.

use std::fmt;
use std::future::Future;
use std::pin::Pin;
use std::time::Duration;

use serde::{Deserialize, Serialize};

use crate::ai::catalog;

pub type BoxFuture<'a, T> = Pin<Box<dyn Future<Output = T> + Send + 'a>>;

/// Where an answer comes from. Every reply in the chat is labelled with it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Placement {
    Local,
    Network,
    Cloud,
}

impl Placement {
    pub fn as_str(self) -> &'static str {
        match self {
            Placement::Local => "local",
            Placement::Network => "network",
            Placement::Cloud => "cloud",
        }
    }
}

/// The contract's error kinds, spelled exactly as in tests/fixtures/ai/.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ErrorKind {
    Offline,
    Unreachable,
    Timeout,
    Server,
    RateLimited,
    Overloaded,
    Auth,
    BadRequest,
    Billing,
    Refusal,
    Cancelled,
    Interrupted,
}

impl ErrorKind {
    /// A failure that a local model may answer instead (spec §5).
    pub fn is_temporary(self) -> bool {
        matches!(
            self,
            ErrorKind::Offline
                | ErrorKind::Unreachable
                | ErrorKind::Timeout
                | ErrorKind::Server
                | ErrorKind::RateLimited
                | ErrorKind::Overloaded
        )
    }

    pub fn as_str(self) -> &'static str {
        match self {
            ErrorKind::Offline => "offline",
            ErrorKind::Unreachable => "unreachable",
            ErrorKind::Timeout => "timeout",
            ErrorKind::Server => "server",
            ErrorKind::RateLimited => "rate_limited",
            ErrorKind::Overloaded => "overloaded",
            ErrorKind::Auth => "auth",
            ErrorKind::BadRequest => "bad_request",
            ErrorKind::Billing => "billing",
            ErrorKind::Refusal => "refusal",
            ErrorKind::Cancelled => "cancelled",
            ErrorKind::Interrupted => "interrupted",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Finish {
    Stop,
    Length,
    ToolCalls,
    Refusal,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Capabilities {
    pub tools: bool,
    pub vision: bool,
    pub json: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelInfo {
    pub id: String,
    /// What the picker and the reply caption show. The id when the server gives no name.
    pub display_name: String,
    pub context_tokens: Option<u64>,
    pub capabilities: Capabilities,
}

impl ModelInfo {
    pub fn named(id: &str) -> Self {
        ModelInfo {
            id: id.to_string(),
            display_name: id.to_string(),
            context_tokens: None,
            capabilities: Capabilities::default(),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Role {
    User,
    Assistant,
}

/// One piece of a message. A dropped file becomes one of the last three.
#[derive(Debug, Clone, PartialEq)]
pub enum Part {
    Text(String),
    /// A file's extracted text, already cut to the model's budget.
    FileText { name: String, text: String },
    Image { name: String, mime: String, base64: String },
    /// A PDF passed through untouched, for providers that read PDFs natively.
    Pdf { name: String, base64: String },
}

#[derive(Debug, Clone, PartialEq)]
pub struct Message {
    pub role: Role,
    pub parts: Vec<Part>,
}

impl Message {
    /// Every text part joined, for providers that take plain-string content.
    pub fn plain_text(&self) -> String {
        let mut out = Vec::new();
        for part in &self.parts {
            match part {
                Part::Text(t) => out.push(t.clone()),
                Part::FileText { name, text } => out.push(file_text(name, text)),
                Part::Image { name, .. } | Part::Pdf { name, .. } => out.push(file_label(name)),
            }
        }
        out.join("\n\n")
    }
}

/// How a file's text is introduced to every model, so all providers read it the same way.
pub fn file_text(name: &str, text: &str) -> String {
    format!("File: {name}\n\n{text}")
}

pub fn file_label(name: &str) -> String {
    format!("File: {name}")
}

/// A client-side tool. Unused in E1; F's cats will send them.
#[derive(Debug, Clone, PartialEq)]
pub struct ToolSpec {
    pub name: String,
    pub description: String,
    pub parameters: serde_json::Value,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ChatRequest {
    pub model: String,
    pub system: String,
    pub messages: Vec<Message>,
    /// Unused in E1 (F adds tools); kept so the interface does not change later.
    pub tools: Vec<ToolSpec>,
    /// A JSON schema for structured output. Unused in E1.
    pub response_format: Option<serde_json::Value>,
    pub max_tokens: u32,
}

/// One tool step Claude Code takes on its own (reading a file, running a command), shown as a row in the chat.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Step {
    pub id: String,
    pub tool: String,
    /// Only the fields that say what the step does (command, file_path, path, query, pattern, url), each cut to 200
    /// Unicode scalars: never a file's content.
    pub input: std::collections::BTreeMap<String, String>,
    pub state: StepState,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum StepState {
    Running,
    Done,
    Failed,
    /// Never sent by this app today; kept so the wire format matches the Mac's.
    #[allow(dead_code)]
    Stopped,
}

/// Who pays for a Claude Code run, as its own first event says.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Payer {
    Plan,
    ApiKey,
    Unknown,
}

/// What a Claude Code run says about itself in `system/init`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EngineReport {
    pub session_id: String,
    pub model: String,
    pub paid_by: Payer,
    pub version: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum ChatChunk {
    Text(String),
    ToolCall { index: usize, id: String, name: String, arguments: String },
    Citation { url: String, title: String },
    Refusal(String),
    Finish(Finish),
    Error(ErrorKind),
    /// A step Claude Code is taking, or has finished (the same `id` updates the same row).
    Step(Step),
    /// What the engine reported about the run it started.
    Engine(EngineReport),
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ToolCall {
    pub id: String,
    pub name: String,
    pub arguments: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Citation {
    pub url: String,
    pub title: String,
}

/// A whole stream folded into one result: the shape of the `.expected.json` fixtures.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Aggregate {
    pub text: String,
    pub tool_calls: Vec<ToolCall>,
    pub citations: Vec<Citation>,
    pub refusal: Option<String>,
    pub finish: Option<Finish>,
    pub error: Option<ErrorKind>,
}

/// A failure before any of the reply arrived. Carries nothing the user typed.
#[derive(Debug, Clone, PartialEq)]
pub struct AiError {
    pub kind: ErrorKind,
    pub status: Option<u16>,
    pub retry_after: Option<u64>,
    /// `x-request-id` / `request-id`, logged for support.
    pub request_id: Option<String>,
    /// The provider's own short error message (never our prompt), for bad requests and billing.
    pub detail: Option<String>,
    /// The provider's error code, e.g. `insufficient_quota`.
    pub code: Option<String>,
    /// When a usage limit resets, in Unix seconds (the Claude plan's limit), so the chat can say when.
    pub resets_at: Option<u64>,
    /// Claude Code took steps before it failed: whatever they did stays done, so Auto must not hand the
    /// question to another model.
    pub after_steps: bool,
}

impl AiError {
    pub fn new(kind: ErrorKind) -> Self {
        AiError { kind, status: None, retry_after: None, request_id: None, detail: None, code: None, resets_at: None, after_steps: false }
    }
}

/// Connection and first-token limits. Spec §5: local 5 s / 60 s, cloud 10 s / 30 s.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Timeouts {
    pub connect: Duration,
    pub first_token: Duration,
    /// Silence after the first token that counts as a cut stream.
    pub idle: Duration,
}

impl Timeouts {
    pub fn for_placement(placement: Placement) -> Self {
        let (connect, first) = match placement {
            Placement::Cloud => (catalog::CONNECT_CLOUD_MS, catalog::FIRST_TOKEN_CLOUD_MS),
            Placement::Local | Placement::Network => {
                (catalog::CONNECT_LOCAL_MS, catalog::FIRST_TOKEN_LOCAL_MS)
            }
        };
        Timeouts {
            connect: Duration::from_millis(connect),
            first_token: Duration::from_millis(first),
            idle: Duration::from_secs(120),
        }
    }
}

/// Everything a provider needs to reach one model. Keys stay in here, on the Rust side.
///
/// `Debug` is written by hand: a derived one would print the key into any failed
/// assertion, panic message or `{:?}` log line.
#[derive(Clone, PartialEq)]
pub struct Endpoint {
    /// Catalog id: anthropic, openai, google, ollama, lmstudio, llamacpp, jan or custom.
    pub provider: String,
    /// "Ollama", "LM Studio", "Local server (OpenAI-compatible)", "Anthropic"…
    pub name: String,
    pub base_url: String,
    pub key: Option<String>,
    pub placement: Placement,
    pub timeouts: Timeouts,
}

impl fmt::Debug for Endpoint {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Endpoint")
            .field("provider", &self.provider)
            .field("name", &self.name)
            // The host only: a URL typed in by hand could once have carried `user:pass@`.
            .field("host", &reqwest::Url::parse(&self.base_url).ok().and_then(|u| u.host_str().map(str::to_string)))
            .field("key", &self.key.as_ref().map(|_| "<redacted>"))
            .field("placement", &self.placement)
            .field("timeouts", &self.timeouts)
            .finish()
    }
}

pub trait ModelProvider: Send + Sync {
    fn id(&self) -> &str;
    /// Part of the shared interface (spec §1); F's assistant shows it.
    #[allow(dead_code)]
    fn display_name(&self) -> &str;
    fn placement(&self) -> Placement;
    fn list_models(&self) -> BoxFuture<'_, Result<Vec<ModelInfo>, AiError>>;
    /// Streams one reply into `sink`. `Err` means nothing arrived; a stream that
    /// breaks after the first token returns `Ok` with `Aggregate::error` set.
    fn stream<'a>(
        &'a self,
        request: &'a ChatRequest,
        sink: &'a mut (dyn FnMut(ChatChunk) + Send),
    ) -> BoxFuture<'a, Result<Aggregate, AiError>>;
    /// Loads a local model ahead of the first message. A no-op where it isn't needed.
    fn prewarm<'a>(&'a self, _model: &'a str) -> BoxFuture<'a, ()> {
        Box::pin(async {})
    }
}

/// The HTTP client for one endpoint. Local and network servers bypass any system
/// proxy. Nothing here sets an `Origin` header: Ollama refuses Windows' webview
/// origin, which is why every model call goes through Rust.
pub fn http_client(endpoint: &Endpoint, total: Option<Duration>) -> reqwest::Client {
    let mut b = reqwest::Client::builder().connect_timeout(endpoint.timeouts.connect);
    if endpoint.placement != Placement::Cloud {
        b = b.no_proxy();
    }
    if let Some(t) = total {
        b = b.timeout(t);
    }
    b.build().unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_endpoint_never_prints_its_key() {
        let endpoint = Endpoint {
            provider: "custom".into(),
            name: "studio-pc".into(),
            base_url: "http://me:hunter2@studio-pc:11434".into(),
            key: Some("sk-live-SECRET".into()),
            placement: Placement::Network,
            timeouts: Timeouts::for_placement(Placement::Network),
        };
        for printed in [format!("{endpoint:?}"), format!("{endpoint:#?}")] {
            assert!(!printed.contains("sk-live-SECRET"), "the key was printed: {printed}");
            assert!(!printed.contains("hunter2"), "a URL password was printed: {printed}");
            assert!(printed.contains("<redacted>") && printed.contains("studio-pc"), "{printed}");
        }
        let keyless = Endpoint { key: None, ..endpoint };
        assert!(format!("{keyless:?}").contains("key: None"));
    }
}
