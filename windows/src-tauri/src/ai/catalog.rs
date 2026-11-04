// The provider catalog: ids, URLs, ports, defaults, filters and limits.
// tests/fixtures/ai/providers.json is the source of truth shared with the macOS
// app; `catalog_matches_providers_json` fails if this table drifts from it.

use serde_json::{json, Value};

use crate::ai::provider::{Capabilities, ModelInfo, Placement};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Api {
    Anthropic,
    OpenAIResponses,
    OpenAIChat,
    Apple,
    /// The user's own Claude Code, run as a process (never a URL).
    ClaudeCode,
    /// The user's own Codex, run as a process. Its engine is F3a2-tauri (1.1): nothing routes here yet.
    Codex,
}

#[cfg(test)]
impl Api {
    pub fn as_str(self) -> &'static str {
        match self {
            Api::Anthropic => "anthropic",
            Api::OpenAIResponses => "openai-responses",
            Api::OpenAIChat => "openai-chat",
            Api::Apple => "apple",
            Api::ClaudeCode => "claude-code",
            Api::Codex => "codex",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CatalogPlacement {
    Local,
    Cloud,
    /// `custom`: local on 127.0.0.1 / ::1 / localhost, network anywhere else.
    Computed,
}

#[cfg(test)]
impl CatalogPlacement {
    pub fn as_str(self) -> &'static str {
        match self {
            CatalogPlacement::Local => "local",
            CatalogPlacement::Cloud => "cloud",
            CatalogPlacement::Computed => "computed",
        }
    }
}

#[derive(Debug, Clone, Copy)]
pub struct ProviderDef {
    pub id: &'static str,
    pub name: &'static str,
    pub placement: CatalogPlacement,
    pub api: Api,
    pub base_url: Option<&'static str>,
    /// Already part of `base_url`; kept so the table reads like providers.json.
    #[cfg_attr(not(test), allow(dead_code))]
    pub port: Option<u16>,
    pub probe_path: Option<&'static str>,
    pub chat_path: Option<&'static str>,
    pub models_path: Option<&'static str>,
    /// providers.json `keychainKey`. For `custom` it is a prefix: use `keychain_name`.
    pub keychain_key: Option<&'static str>,
    pub default_model: Option<&'static str>,
}

pub const PROVIDERS: &[ProviderDef] = &[
    ProviderDef {
        id: "anthropic", name: "Anthropic", placement: CatalogPlacement::Cloud, api: Api::Anthropic,
        base_url: Some("https://api.anthropic.com"), port: None, probe_path: None,
        chat_path: Some("/v1/messages"), models_path: Some("/v1/models"),
        keychain_key: Some("anthropic-api-key"), default_model: Some("claude-sonnet-5-5"),
    },
    ProviderDef {
        id: "openai", name: "OpenAI", placement: CatalogPlacement::Cloud, api: Api::OpenAIResponses,
        base_url: Some("https://api.openai.com"), port: None, probe_path: None,
        chat_path: Some("/v1/responses"), models_path: Some("/v1/models"),
        keychain_key: Some("openai-api-key"), default_model: Some("gpt-6.1-sol"),
    },
    ProviderDef {
        id: "google", name: "Google", placement: CatalogPlacement::Cloud, api: Api::OpenAIChat,
        base_url: Some("https://generativelanguage.googleapis.com/v1beta/openai"), port: None, probe_path: None,
        chat_path: Some("/chat/completions"), models_path: Some("/models"),
        keychain_key: Some("google-api-key"), default_model: None,
    },
    ProviderDef {
        id: "ollama", name: "Ollama", placement: CatalogPlacement::Local, api: Api::OpenAIChat,
        base_url: Some("http://127.0.0.1:11434"), port: Some(11434), probe_path: Some("/api/version"),
        chat_path: Some("/v1/chat/completions"), models_path: Some("/v1/models"),
        keychain_key: None, default_model: None,
    },
    ProviderDef {
        id: "lmstudio", name: "LM Studio", placement: CatalogPlacement::Local, api: Api::OpenAIChat,
        base_url: Some("http://127.0.0.1:1234"), port: Some(1234), probe_path: Some("/v1/models"),
        chat_path: Some("/v1/chat/completions"), models_path: Some("/v1/models"),
        keychain_key: None, default_model: None,
    },
    ProviderDef {
        id: "llamacpp", name: "llama.cpp", placement: CatalogPlacement::Local, api: Api::OpenAIChat,
        base_url: Some("http://127.0.0.1:8080"), port: Some(8080), probe_path: Some("/health"),
        chat_path: Some("/v1/chat/completions"), models_path: Some("/v1/models"),
        keychain_key: None, default_model: None,
    },
    ProviderDef {
        id: "jan", name: "Jan", placement: CatalogPlacement::Local, api: Api::OpenAIChat,
        base_url: Some("http://127.0.0.1:1337"), port: Some(1337), probe_path: Some("/v1/models"),
        chat_path: Some("/v1/chat/completions"), models_path: Some("/v1/models"),
        keychain_key: None, default_model: None,
    },
    ProviderDef {
        id: "apple", name: "Apple on-device", placement: CatalogPlacement::Local, api: Api::Apple,
        base_url: None, port: None, probe_path: None, chat_path: None, models_path: None,
        keychain_key: None, default_model: Some("system"),
    },
    ProviderDef {
        id: "custom", name: "Local server", placement: CatalogPlacement::Computed, api: Api::OpenAIChat,
        base_url: None, port: None, probe_path: None,
        chat_path: Some("/v1/chat/completions"), models_path: Some("/v1/models"),
        keychain_key: Some("custom-server-key"), default_model: None,
    },
    ProviderDef {
        id: "claudeCode", name: "Claude plan", placement: CatalogPlacement::Cloud, api: Api::ClaudeCode,
        base_url: None, port: None, probe_path: None, chat_path: None, models_path: None,
        keychain_key: None, default_model: Some("sonnet"),
    },
    ProviderDef {
        id: "codexPlan", name: "OpenAI plan", placement: CatalogPlacement::Cloud, api: Api::Codex,
        base_url: None, port: None, probe_path: None, chat_path: None, models_path: None,
        keychain_key: None, default_model: None,
    },
];

/// Auto's cloud order before the Preferred cloud is moved to the front.
pub const CLOUD_ORDER: [&str; 3] = ["anthropic", "openai", "google"];
/// Servers checked on 127.0.0.1, in this order.
pub const LOCAL_SERVERS: [&str; 4] = ["ollama", "lmstudio", "llamacpp", "jan"];

pub const LOCAL_EXCLUDE: &[&str] = &["embed", "bge-", "all-minilm", "clip", "rerank"];
pub const GOOGLE_EXCLUDE: &[&str] = &["embed", "imagen", "veo", "aqa", "tts", "audio", "live"];
pub const OPENAI_INCLUDE_PREFIXES: &[&str] = &["gpt-", "o1", "o3", "o4", "o5"];
pub const OPENAI_EXCLUDE: &[&str] = &[
    "embed", "tts", "whisper", "dall-e", "audio", "realtime", "moderat", "codex", "computer-use",
    "transcribe", "image", "sora", "babbage", "davinci", "instruct", "search", "live",
];

pub const PROBE_MS: u64 = 300;
/// A server the user added: probed in parallel with the localhost phase, but a slow LAN host still counts.
pub const ADDED_PROBE_MS: u64 = 2_000;
pub const CONNECT_LOCAL_MS: u64 = 5_000;
pub const CONNECT_CLOUD_MS: u64 = 10_000;
pub const FIRST_TOKEN_LOCAL_MS: u64 = 60_000;
pub const FIRST_TOKEN_CLOUD_MS: u64 = 30_000;

pub const MAX_FILE_BYTES: u64 = 26_214_400;
pub const CLOUD_TEXT_CAP_CHARS: usize = 204_800;
/// A file's text budget is `ctx × 7 / 4` characters: half the context at 3.5 characters per token
/// (providers.json `budgetFractionOfContext` × `charsPerToken`), in integers so no platform rounds differently.
pub const BUDGET_CHARS_NUMERATOR: u64 = 7;
pub const BUDGET_CHARS_DENOMINATOR: u64 = 4;
pub const DEFAULT_LOCAL_CONTEXT_TOKENS: u64 = 4_096;

/// providers.json `maxOutputTokens`: the reply length asked for, by the placement of the model.
/// Cloud gets more because OpenAI's reasoning models spend hidden reasoning tokens from the cap;
/// 4,096 for local and network is what the Mac's `LocalChat` already sends.
pub const MAX_OUTPUT_TOKENS_CLOUD: u32 = 16_000;
pub const MAX_OUTPUT_TOKENS_NETWORK: u32 = 4_096;
pub const MAX_OUTPUT_TOKENS_LOCAL: u32 = 4_096;

/// Environment variable that points the cloud providers at a test server.
/// Debug builds only: release builds don't even contain the name.
#[cfg(debug_assertions)]
pub const BASE_URL_OVERRIDE_VAR: &str = "NM_AI_BASE_URL_OVERRIDE";

pub fn get(id: &str) -> Option<&'static ProviderDef> {
    PROVIDERS.iter().find(|p| p.id == id)
}

/// The cloud providers, and Claude Code, which runs on Anthropic's servers through the user's own program.
pub fn is_cloud(id: &str) -> bool {
    CLOUD_ORDER.contains(&id) || id == "claudeCode"
}

/// The name used in "… is busy" and "… will read this": the product for Claude,
/// the company otherwise.
pub fn brand(id: &str) -> &'static str {
    match id {
        "anthropic" | "claudeCode" => "Claude",
        other => get(other).map(|p| p.name).unwrap_or("The server"),
    }
}

/// Where "Open billing page" goes.
pub fn billing_url(id: &str) -> Option<&'static str> {
    match id {
        "anthropic" => Some("https://console.anthropic.com/settings/billing"),
        "openai" => Some("https://platform.openai.com/settings/organization/billing/overview"),
        "google" => Some("https://aistudio.google.com/"),
        _ => None,
    }
}

/// The debug-only redirect of the cloud providers. Always `None` in release builds.
pub fn debug_override() -> Option<String> {
    #[cfg(debug_assertions)]
    {
        std::env::var(BASE_URL_OVERRIDE_VAR).ok().filter(|v| !v.trim().is_empty())
    }
    #[cfg(not(debug_assertions))]
    {
        None
    }
}

/// A cloud provider's base URL, or the override's root when one is given. Google's
/// paths are relative to an OpenAI-style root, so its override gains `/v1`.
pub fn base_url(id: &str, override_root: Option<&str>) -> Option<String> {
    let def = get(id)?;
    if let (Some(root), CatalogPlacement::Cloud) = (override_root, def.placement) {
        let root = root.trim_end_matches('/');
        return Some(if id == "google" { format!("{root}/v1") } else { root.to_string() });
    }
    def.base_url.map(str::to_string)
}

/// 127.0.0.1, ::1 and localhost are this computer; anything else is the network.
pub fn is_local_host(host: &str) -> bool {
    let host = host.trim_start_matches('[').trim_end_matches(']').to_ascii_lowercase();
    host == "127.0.0.1" || host == "::1" || host == "localhost"
}

/// Keeps chat models only (spec §2: embedding models are filtered out).
pub fn filter_models(provider: &str, models: Vec<ModelInfo>) -> Vec<ModelInfo> {
    models
        .into_iter()
        .filter(|m| {
            let id = m.id.to_ascii_lowercase();
            match provider {
                "anthropic" => true,
                "openai" => {
                    OPENAI_INCLUDE_PREFIXES.iter().any(|p| id.starts_with(p))
                        && !OPENAI_EXCLUDE.iter().any(|x| id.contains(x))
                }
                "google" => !GOOGLE_EXCLUDE.iter().any(|x| id.contains(x)),
                _ => !LOCAL_EXCLUDE.iter().any(|x| id.contains(x)),
            }
        })
        .collect()
}

/// The model Auto uses when the user never picked one. Google's rule: the first id
/// containing "flash", else the first.
pub fn default_model(provider: &str, available: &[ModelInfo]) -> Option<String> {
    if let Some(m) = get(provider).and_then(|p| p.default_model) {
        return Some(m.to_string());
    }
    if provider == "google" {
        return available
            .iter()
            .find(|m| m.id.contains("flash"))
            .or_else(|| available.first())
            .map(|m| m.id.clone());
    }
    available.first().map(|m| m.id.clone())
}

/// providers.json `webSearch.anthropic`: `web_search_20260209` needs a recent Claude model, so a
/// model ID starting with one of these prefixes gets the legacy type instead.
pub const WEB_SEARCH_ANTHROPIC: &str = "web_search_20260209";
pub const WEB_SEARCH_ANTHROPIC_LEGACY: &str = "web_search_20250305";
pub const LEGACY_WEB_SEARCH_PREFIXES: &[&str] = &["claude-haiku-4", "claude-3"];

/// The contract's `anthropicWebSearchType(model)`.
pub fn anthropic_web_search_type(model: &str) -> &'static str {
    if LEGACY_WEB_SEARCH_PREFIXES.iter().any(|p| model.starts_with(p)) {
        WEB_SEARCH_ANTHROPIC_LEGACY
    } else {
        WEB_SEARCH_ANTHROPIC
    }
}

/// The hosted web-search tool a cloud provider's request carries, as providers.json
/// `webSearch` spells it (`web_search_tools_match_the_contract` compares them). Claude and
/// OpenAI search the web themselves; no other provider gets a tool.
pub fn web_search_tools(provider: &str, model: &str) -> Vec<Value> {
    match provider {
        "anthropic" => vec![json!({ "type": anthropic_web_search_type(model), "name": "web_search", "max_uses": 5 })],
        "openai" => vec![json!({ "type": "web_search" })],
        _ => Vec::new(),
    }
}

/// Cloud models all read images and PDFs; their lists carry no capability fields.
pub fn cloud_capabilities() -> Capabilities {
    Capabilities { tools: true, vision: true, json: true }
}

/// Anthropic and OpenAI take PDFs as-is; everyone else gets extracted text.
pub fn reads_pdf_natively(provider: &str) -> bool {
    provider == "anthropic" || provider == "openai" || provider == "claudeCode"
}

pub fn placement_of(id: &str, host: Option<&str>) -> Placement {
    match get(id).map(|p| p.placement) {
        Some(CatalogPlacement::Cloud) => Placement::Cloud,
        Some(CatalogPlacement::Computed) => match host {
            Some(h) if !is_local_host(h) => Placement::Network,
            _ => Placement::Local,
        },
        _ => Placement::Local,
    }
}

/// `max_tokens` for a request to a model at this placement: providers.json `maxOutputTokens`.
pub fn max_output_tokens(placement: Placement) -> u32 {
    match placement {
        Placement::Cloud => MAX_OUTPUT_TOKENS_CLOUD,
        Placement::Network => MAX_OUTPUT_TOKENS_NETWORK,
        Placement::Local => MAX_OUTPUT_TOKENS_LOCAL,
    }
}

/// The id the one added server is stored under. The contract allows several (ids match
/// `^[a-z0-9-]{1,32}$`, one keychain item each); this app offers one.
pub const CUSTOM_SERVER_ID: &str = "default";

/// The keychain item a provider's key lives in. providers.json gives `custom` the prefix
/// `custom-server-key`, so the added server's item is `custom-server-key.<serverId>`.
pub fn keychain_name(id: &str) -> Option<String> {
    let key = get(id)?.keychain_key?;
    Some(if id == "custom" { format!("{key}.{CUSTOM_SERVER_ID}") } else { key.to_string() })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ai::testkit;
    use serde_json::Value;

    fn opt(v: Option<&str>) -> Value {
        v.map(|s| Value::String(s.into())).unwrap_or(Value::Null)
    }

    #[test]
    fn catalog_matches_providers_json() {
        let json = testkit::load_json("providers.json");
        let listed = json["providers"].as_array().unwrap();
        assert_eq!(listed.len(), PROVIDERS.len(), "provider count");
        for (want, have) in listed.iter().zip(PROVIDERS) {
            let id = have.id;
            assert_eq!(want["id"], id);
            assert_eq!(want["name"], have.name, "{id} name");
            assert_eq!(want["placement"], have.placement.as_str(), "{id} placement");
            assert_eq!(want["api"], have.api.as_str(), "{id} api");
            assert_eq!(want.get("baseURL").cloned().unwrap_or(Value::Null), opt(have.base_url), "{id} baseURL");
            assert_eq!(want.get("port").and_then(Value::as_u64), have.port.map(u64::from), "{id} port");
            assert_eq!(want.get("probePath").cloned().unwrap_or(Value::Null), opt(have.probe_path), "{id} probePath");
            assert_eq!(want.get("chatPath").cloned().unwrap_or(Value::Null), opt(have.chat_path), "{id} chatPath");
            assert_eq!(want.get("modelsPath").cloned().unwrap_or(Value::Null), opt(have.models_path), "{id} modelsPath");
            assert_eq!(want["keychainKey"], opt(have.keychain_key), "{id} keychainKey");
            assert_eq!(want["defaultModel"], opt(have.default_model), "{id} defaultModel");
        }
        let order: Vec<&str> = json["cloudOrder"].as_array().unwrap().iter().map(|v| v.as_str().unwrap()).collect();
        assert_eq!(order, CLOUD_ORDER);

        let strs = |v: &Value| -> Vec<String> { v.as_array().unwrap().iter().map(|s| s.as_str().unwrap().to_string()).collect() };
        let filters = &json["modelFilters"];
        assert_eq!(strs(&filters["local"]["exclude"]), LOCAL_EXCLUDE);
        assert_eq!(strs(&filters["google"]["exclude"]), GOOGLE_EXCLUDE);
        assert_eq!(strs(&filters["openai"]["includePrefixes"]), OPENAI_INCLUDE_PREFIXES);
        assert_eq!(strs(&filters["openai"]["exclude"]), OPENAI_EXCLUDE);

        let t = &json["timeoutsMs"];
        assert_eq!(t["probe"], PROBE_MS);
        assert_eq!(t["connectLocal"], CONNECT_LOCAL_MS);
        assert_eq!(t["connectCloud"], CONNECT_CLOUD_MS);
        assert_eq!(t["firstTokenLocal"], FIRST_TOKEN_LOCAL_MS);
        assert_eq!(t["firstTokenCloud"], FIRST_TOKEN_CLOUD_MS);

        let l = &json["limits"];
        assert_eq!(l["maxFileBytes"], MAX_FILE_BYTES);
        assert_eq!(l["cloudTextCapChars"].as_u64(), Some(CLOUD_TEXT_CAP_CHARS as u64));
        // 0.5 × 3.5 = 7/4: the budget is `ctx × 7 / 4` characters, in integers.
        let per_context = l["budgetFractionOfContext"].as_f64().unwrap() * l["charsPerToken"].as_f64().unwrap();
        assert_eq!(per_context * BUDGET_CHARS_DENOMINATOR as f64, BUDGET_CHARS_NUMERATOR as f64);
        assert_eq!(l["defaultLocalContextTokens"], DEFAULT_LOCAL_CONTEXT_TOKENS);
    }

    #[test]
    fn web_search_tools_match_the_contract() {
        let json = testkit::load_json("providers.json");
        let ws = &json["webSearch"];
        assert_eq!(ws.as_object().unwrap().len(), 2, "providers.json gained a web-search provider: give it a tool here");
        // OpenAI: exactly the contract's object.
        assert_eq!(web_search_tools("openai", "gpt-6.1-sol"), vec![ws["openai"].clone()]);
        // Anthropic: the contract's type, name and max_uses for a current model…
        let claude = &ws["anthropic"];
        let tool = |ty: &Value| json!({ "type": ty, "name": claude["name"], "max_uses": claude["max_uses"] });
        assert_eq!(web_search_tools("anthropic", "claude-sonnet-5-5"), vec![tool(&claude["type"])]);
        // …and `legacyType` for the model prefixes the contract lists.
        assert_eq!(claude["legacyType"], WEB_SEARCH_ANTHROPIC_LEGACY);
        let prefixes: Vec<&str> = claude["legacyModelPrefixes"].as_array().unwrap().iter().map(|p| p.as_str().unwrap()).collect();
        assert_eq!(prefixes, LEGACY_WEB_SEARCH_PREFIXES);
        for model in ["claude-haiku-4-5-20251001", "claude-3-7-sonnet"] {
            assert_eq!(web_search_tools("anthropic", model), vec![tool(&claude["legacyType"])], "{model}");
        }
        assert!(web_search_tools("google", "gemini").is_empty() && web_search_tools("ollama", "qwen3.5:2b").is_empty());
    }

    #[test]
    fn reply_length_follows_the_contract() {
        let json = testkit::load_json("providers.json");
        let lengths = json["maxOutputTokens"].as_object().unwrap();
        assert_eq!(lengths.len(), 3, "providers.json gained a placement: give it a reply length here");
        for placement in [Placement::Cloud, Placement::Network, Placement::Local] {
            assert_eq!(lengths[placement.as_str()], max_output_tokens(placement), "{}", placement.as_str());
        }
    }

    /// Pinned on purpose, so that an edit to providers.json (or to the constants) is noticed and decided on:
    /// OpenAI's reasoning models spend hidden reasoning tokens from the cap, and 4,096 is what the Mac's
    /// `LocalChat` already sends to local models.
    #[test]
    fn reply_length_is_16000_for_cloud_and_4096_for_local() {
        assert_eq!(max_output_tokens(Placement::Cloud), 16_000);
        assert_eq!(max_output_tokens(Placement::Local), 4_096);
        assert_eq!(max_output_tokens(Placement::Network), 4_096);
    }

    #[test]
    fn the_added_servers_keychain_item_is_the_prefix_plus_its_id() {
        // providers.json says `custom-server-key`; each added server is stored as `<that>.<serverId>`.
        assert_eq!(keychain_name("custom").as_deref(), Some("custom-server-key.default"));
        assert_eq!(keychain_name("anthropic").as_deref(), Some("anthropic-api-key"));
        assert_eq!(keychain_name("google").as_deref(), Some("google-api-key"));
        assert_eq!(keychain_name("ollama"), None);
        assert_eq!(keychain_name("nope"), None);
    }

    #[test]
    fn claude_code_is_cloud_without_a_key_or_a_url() {
        let def = get("claudeCode").unwrap();
        assert_eq!((def.placement, def.api, def.keychain_key, def.base_url), (CatalogPlacement::Cloud, Api::ClaudeCode, None, None));
        assert!(is_cloud("claudeCode") && reads_pdf_natively("claudeCode"));
        assert_eq!(brand("claudeCode"), "Claude");
        assert_eq!(default_model("claudeCode", &[]).as_deref(), Some("sonnet"));
        assert_eq!(keychain_name("claudeCode"), None, "there is no key to read: a key would be a login");
        assert_eq!(placement_of("claudeCode", None), Placement::Cloud);
    }

    #[test]
    fn local_servers_are_the_catalog_ports_in_order() {
        let ports: Vec<u16> = LOCAL_SERVERS.iter().map(|id| get(id).unwrap().port.unwrap()).collect();
        assert_eq!(ports, [11434, 1234, 8080, 1337]);
    }

    #[test]
    fn filters_drop_embeddings_and_non_chat_models() {
        let ids = |v: Vec<ModelInfo>| v.into_iter().map(|m| m.id).collect::<Vec<_>>();
        let local = vec![ModelInfo::named("llama3.2"), ModelInfo::named("nomic-embed-text"), ModelInfo::named("bge-m3")];
        assert_eq!(ids(filter_models("ollama", local)), ["llama3.2"]);
        let openai = vec![
            ModelInfo::named("gpt-6.1-sol"), ModelInfo::named("text-embedding-3-large"),
            ModelInfo::named("gpt-6-audio-preview"), ModelInfo::named("o5-mini"), ModelInfo::named("dall-e-3"),
        ];
        assert_eq!(ids(filter_models("openai", openai)), ["gpt-6.1-sol", "o5-mini"]);
        let google = vec![ModelInfo::named("gemini-3-flash"), ModelInfo::named("imagen-4"), ModelInfo::named("gemini-3-pro")];
        assert_eq!(ids(filter_models("google", google)), ["gemini-3-flash", "gemini-3-pro"]);
    }

    #[test]
    fn default_models_follow_the_catalog() {
        assert_eq!(default_model("anthropic", &[]).as_deref(), Some("claude-sonnet-5-5"));
        assert_eq!(default_model("openai", &[]).as_deref(), Some("gpt-6.1-sol"));
        let google = [ModelInfo::named("gemini-3-pro"), ModelInfo::named("gemini-3-flash")];
        assert_eq!(default_model("google", &google).as_deref(), Some("gemini-3-flash"));
        assert_eq!(default_model("google", &google[..1]).as_deref(), Some("gemini-3-pro"));
        assert_eq!(default_model("google", &[]), None);
    }

    #[test]
    fn override_redirects_cloud_only() {
        assert_eq!(base_url("openai", None).as_deref(), Some("https://api.openai.com"));
        assert_eq!(base_url("openai", Some("http://127.0.0.1:9/")).as_deref(), Some("http://127.0.0.1:9"));
        assert_eq!(base_url("anthropic", Some("http://127.0.0.1:9")).as_deref(), Some("http://127.0.0.1:9"));
        assert_eq!(base_url("google", Some("http://127.0.0.1:9")).as_deref(), Some("http://127.0.0.1:9/v1"));
        assert_eq!(base_url("ollama", Some("http://127.0.0.1:9")).as_deref(), Some("http://127.0.0.1:11434"));
    }

    /// `cargo test --release` runs this one: a shipped app can't be redirected.
    #[cfg(not(debug_assertions))]
    #[test]
    fn release_builds_ignore_the_override() {
        let _override = crate::testenv::EnvGuard::set(BASE_URL_OVERRIDE_VAR, "http://127.0.0.1:9");
        assert_eq!(debug_override(), None);
    }

    #[cfg(debug_assertions)]
    #[test]
    fn debug_builds_read_the_override() {
        assert_eq!(BASE_URL_OVERRIDE_VAR, "NM_AI_BASE_URL_OVERRIDE");
    }

    #[test]
    fn custom_placement_depends_on_the_host() {
        assert_eq!(placement_of("custom", Some("127.0.0.1")), Placement::Local);
        assert_eq!(placement_of("custom", Some("[::1]")), Placement::Local);
        assert_eq!(placement_of("custom", Some("LOCALHOST")), Placement::Local);
        assert_eq!(placement_of("custom", Some("studio-pc")), Placement::Network);
        assert_eq!(placement_of("google", None), Placement::Cloud);
        assert_eq!(placement_of("jan", None), Placement::Local);
    }
}
