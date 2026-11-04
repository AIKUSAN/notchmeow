// HTTP and transport failures → the contract's error kinds, and the words the
// chat shows for each (spec §5). `classify_http` is `classify_http()` from
// tests/fixtures/ai/reference.py; `http_error_cases` runs http-errors.json.

use serde::Serialize;
use serde_json::{Map, Value};

use crate::ai::catalog;
use crate::ai::provider::{AiError, ErrorKind};

/// The codes (and error types) that mean money, for HTTP errors and mid-stream errors alike.
/// A code that ends in `_spend_limit_exceeded` is billing too: see `is_billing`.
pub const BILLING_CODES: [&str; 4] = [
    "insufficient_quota",
    "credit_balance_exhausted",
    "organization_usage_limit_exceeded",
    "billing_error",
];

/// `reference.py`'s `_is_billing`: the one list `classify_http` and `stream_error_kind` share.
pub fn is_billing(code: &str) -> bool {
    BILLING_CODES.contains(&code) || code.ends_with("_spend_limit_exceeded")
}

/// `AiError::code` when a chosen cloud provider has no key at all.
pub const MISSING_KEY: &str = "missing_key";

/// Seconds Auto waits before retrying a busy cloud when `Retry-After` says nothing.
pub const DEFAULT_RETRY_SECONDS: u64 = 20;

fn header<'a>(headers: &'a [(String, String)], name: &str) -> Option<&'a str> {
    headers.iter().find(|(k, _)| k.eq_ignore_ascii_case(name)).map(|(_, v)| v.as_str())
}

/// An object, or the first element of a list when that is one (Google's OpenAI-compatible endpoint
/// wraps its errors in a list): `reference.py`'s `_first_dict`. Anything else is none.
fn first_object(v: Option<&Value>) -> Option<&Map<String, Value>> {
    match v? {
        Value::Object(map) => Some(map),
        Value::Array(list) => list.first()?.as_object(),
        _ => None,
    }
}

/// The body's `error` object. `{"error":"model not found"}` (LM Studio, Ollama), null, a number
/// or an empty list have none, and nothing here can panic.
fn error_object(body: Option<&Value>) -> Option<&Map<String, Value>> {
    first_object(first_object(body)?.get("error"))
}

pub fn error_field<'a>(body: Option<&'a Value>, field: &str) -> Option<&'a str> {
    error_object(body)?.get(field)?.as_str()
}

/// Rules, in order: a billing marker wins (status 402; an error `code` or `type` that `is_billing`;
/// "credit balance" in the message); 401/403 auth; 400/404/413/422 bad request; 429 rate limited;
/// 503/529 overloaded; other 5xx server; else bad request. `Retry-After` counts only as ASCII
/// digits above 0.
pub fn classify_http(status: u16, body: Option<&Value>, headers: &[(String, String)]) -> (ErrorKind, Option<u64>) {
    // Not `parse` alone: it takes "+5". Not `char::is_numeric`: "\u{b2}" is a digit to Unicode, not to HTTP.
    let retry = header(headers, "retry-after")
        .map(str::trim)
        .filter(|v| !v.is_empty() && v.bytes().all(|b| b.is_ascii_digit()))
        .and_then(|v| v.parse::<u64>().ok())
        .filter(|seconds| *seconds > 0);
    let text = |field: &str| error_field(body, field);
    let billing = text("code").is_some_and(is_billing)
        || text("type").is_some_and(is_billing)
        || status == 402
        || text("message").is_some_and(|m| m.to_lowercase().contains("credit balance"));
    let kind = if billing {
        ErrorKind::Billing
    } else {
        match status {
            401 | 403 => ErrorKind::Auth,
            400 | 404 | 413 | 422 => ErrorKind::BadRequest,
            429 => ErrorKind::RateLimited,
            503 | 529 => ErrorKind::Overloaded,
            500..=599 => ErrorKind::Server,
            _ => ErrorKind::BadRequest,
        }
    };
    (kind, retry)
}

/// The kind of a mid-stream error: an OpenAI `error.code` (Responses `response.failed` and `error`
/// events) or an Anthropic `error.type`; `reference.py`'s `stream_error_kind`. An unknown code is
/// `BadRequest`, never `Server`: `Server` is temporary, so Auto would hand a policy refusal or a
/// rejected key to a local model.
pub fn stream_error_kind(code: &str) -> ErrorKind {
    if is_billing(code) {
        return ErrorKind::Billing;
    }
    match code {
        "rate_limit_exceeded" | "rate_limit_error" => ErrorKind::RateLimited,
        "server_is_overloaded" | "slow_down" | "overloaded_error" => ErrorKind::Overloaded,
        "server_error" | "api_error" | "timeout_error" | "vector_store_timeout" => ErrorKind::Server,
        "invalid_prompt" | "image_content_policy_violation" | "content_policy_violation" | "content_filter" => {
            ErrorKind::Refusal
        }
        "authentication_error" | "invalid_api_key" | "permission_error" => ErrorKind::Auth,
        _ => ErrorKind::BadRequest,
    }
}

/// Connection refused and DNS failures are `unreachable`; slow connects are `timeout`.
pub fn classify_transport(err: &reqwest::Error) -> ErrorKind {
    if err.is_timeout() {
        ErrorKind::Timeout
    } else {
        ErrorKind::Unreachable
    }
}

pub fn from_transport(err: &reqwest::Error) -> AiError {
    AiError::new(classify_transport(err))
}

/// Reads a failed response into an `AiError`. Keeps the provider's own short
/// message (shown for bad requests) but never the request body.
pub async fn from_response(response: reqwest::Response) -> AiError {
    let status = response.status().as_u16();
    let headers: Vec<(String, String)> = response
        .headers()
        .iter()
        .filter_map(|(k, v)| v.to_str().ok().map(|v| (k.as_str().to_string(), v.to_string())))
        .collect();
    let request_id = header(&headers, "x-request-id").or_else(|| header(&headers, "request-id")).map(str::to_string);
    let body: Option<Value> = response.text().await.ok().and_then(|t| serde_json::from_str(&t).ok());
    let (kind, retry_after) = classify_http(status, body.as_ref(), &headers);
    AiError {
        kind,
        status: Some(status),
        retry_after,
        request_id,
        detail: error_field(body.as_ref(), "message").map(|m| m.chars().take(200).collect()),
        code: error_field(body.as_ref(), "code").map(str::to_string),
        resets_at: None,
        after_steps: false,
    }
}

/// What a button under an error does.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(tag = "kind", rename_all = "camelCase", rename_all_fields = "camelCase")]
pub enum Action {
    OpenSettings,
    OpenBilling { url: String },
    OpenGuide,
    ChooseModel,
    Cancel,
    /// Claude Code: open a terminal to sign in, show Anthropic's install page, show its update page, show Git for
    /// Windows' page, or send the last message again.
    SignInClaude,
    InstallClaude,
    UpdateClaude,
    InstallGit,
    TryAgain,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Wording {
    pub text: String,
    pub action: Option<Action>,
}

fn wording(text: String, action: Option<Action>) -> Wording {
    Wording { text, action }
}

/// Who a provider is, in the words the messages use.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Who {
    /// Catalog id.
    pub provider: String,
    /// "Ollama", "LM Studio", "Local server (OpenAI-compatible)", "Anthropic"…
    pub name: String,
}

/// The chat's message for a failure that nothing could answer instead (spec §5's table,
/// plus the cases it leaves out, worded the same way).
pub fn error_copy(kind: ErrorKind, who: &Who, err: Option<&AiError>) -> Wording {
    if who.provider == "claudeCode" {
        if let Some(note) = err.and_then(crate::ai::claude_code::wording) {
            return note;
        }
    }
    let cloud = catalog::is_cloud(&who.provider);
    let brand = if cloud { catalog::brand(&who.provider).to_string() } else { who.name.clone() };
    match kind {
        ErrorKind::Auth => {
            let owner = if cloud { who.name.clone() } else { "server".to_string() };
            let missing = err.and_then(|e| e.code.as_deref()) == Some(MISSING_KEY);
            let text = if missing { format!("Your {owner} key is missing.") } else { format!("Your {owner} key was rejected.") };
            wording(text, Some(Action::OpenSettings))
        }
        ErrorKind::Billing => {
            let spend = err
                .and_then(|e| e.code.as_deref())
                .is_some_and(|c| c.ends_with("_spend_limit_exceeded") || c == "organization_usage_limit_exceeded");
            let text = if spend {
                format!("Your {} spend limit was reached.", who.name)
            } else {
                format!("Your {} credit ran out.", who.name)
            };
            let action = catalog::billing_url(&who.provider).map(|u| Action::OpenBilling { url: u.to_string() });
            wording(text, action)
        }
        ErrorKind::RateLimited | ErrorKind::Overloaded => {
            let secs = err.and_then(|e| e.retry_after).unwrap_or(DEFAULT_RETRY_SECONDS);
            wording(format!("{brand} is busy. Trying again in {secs} s."), Some(Action::Cancel))
        }
        ErrorKind::Offline | ErrorKind::Unreachable if !cloud => {
            wording(format!("Couldn't reach {brand}. Is its server on?"), Some(Action::OpenGuide))
        }
        ErrorKind::Offline | ErrorKind::Unreachable => {
            wording(format!("Couldn't reach {brand}. Check your connection."), None)
        }
        ErrorKind::Timeout => wording(format!("{brand} took too long to answer."), None),
        ErrorKind::Server => wording(format!("{brand} had a problem. Try again in a moment."), None),
        ErrorKind::BadRequest => {
            let detail = err.and_then(|e| e.detail.clone()).unwrap_or_else(|| "it couldn't handle this request.".into());
            wording(format!("{brand}: {detail}"), None)
        }
        ErrorKind::Refusal => wording(format!("{brand} declined this one."), None),
        ErrorKind::Cancelled | ErrorKind::Interrupted => wording(String::new(), None),
    }
}

/// "Claude's busy right now, so Qwen answered instead."
pub fn fallback_copy(primary: &str, fallback_model: &str) -> String {
    format!("{}'s busy right now, so {} answered instead.", catalog::brand(primary), model_family(fallback_model))
}

/// "qwen3.5:2b" → "Qwen", "gemma-4-e2b" → "Gemma"; the whole id when it starts with no letters.
pub fn model_family(model: &str) -> String {
    let letters: String = model.chars().take_while(|c| c.is_ascii_alphabetic()).collect();
    let mut chars = letters.chars();
    match chars.next() {
        Some(first) => first.to_ascii_uppercase().to_string() + chars.as_str(),
        None => model.to_string(),
    }
}

pub const TOO_LONG: &str = "This chat got long, so I dropped the oldest messages.";
pub const CANT_SEE: &str = "This model can't see images. Pick one that can.";

/// The reply came back empty because the model spent every token thinking.
pub const RAN_OUT_OF_ROOM: &str = "The model ran out of room before answering. Try again, or pick a model without thinking mode.";
/// The reply came back empty for any other reason.
pub const EMPTY_REPLY: &str = "The model sent an empty reply. Try again.";
/// The reply stopped at the token limit but has text worth keeping.
pub const CUT_OFF: &str = "The answer was cut off.";

/// Anthropic and OpenAI reject `image/heic`, and local servers can't decode it.
pub const HEIC: &str = "HEIC photos aren't supported yet. Export it as JPEG or PNG.";
pub const SCANNED_PDF_LINUX: &str = "I can't read scanned PDFs on Linux yet. Try Claude or OpenAI, or paste the text.";
pub const SCANNED_PDF_WINDOWS: &str = "I can't read this scanned PDF. Try Claude or OpenAI, or paste the text.";

/// A scanned PDF no model here can be shown: Linux has no PDF renderer and no OCR, and
/// Windows can lack an OCR language. It is not "this model can't see images".
pub fn scanned_pdf_copy() -> &'static str {
    if cfg!(windows) {
        SCANNED_PDF_WINDOWS
    } else {
        SCANNED_PDF_LINUX
    }
}

/// A model the user chose that its server no longer has.
pub fn missing_model_copy(model: &str, server: &str) -> Wording {
    wording(format!("{model} isn't on {server} any more."), Some(Action::ChooseModel))
}

pub fn outdated_copy(name: &str) -> Wording {
    wording(format!("Update {name} to use it here."), Some(Action::OpenGuide))
}

pub fn waking_copy(model: &str) -> String {
    let short = model.split(':').next().unwrap_or(model);
    format!("Waking up {short}…")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ai::testkit;

    #[test]
    fn http_error_cases() {
        let data = testkit::load_json("http-errors.json");
        let cases = data["cases"].as_array().unwrap();
        assert_eq!(cases.len(), 21, "http-errors.json changed: update this count on purpose");
        for case in cases {
            let status = case["status"].as_u64().unwrap() as u16;
            let headers: Vec<(String, String)> = case["headers"]
                .as_object()
                .unwrap()
                .iter()
                .map(|(k, v)| (k.clone(), v.as_str().unwrap().to_string()))
                .collect();
            let body = if case["body"].is_null() { None } else { Some(&case["body"]) };
            let (kind, retry) = classify_http(status, body, &headers);
            assert_eq!(serde_json::to_value(kind).unwrap(), case["kind"], "{status} {}", case["body"]);
            assert_eq!(retry, case["retryAfter"].as_u64(), "{status} retryAfter");
        }
    }

    #[test]
    fn odd_error_bodies_never_panic() {
        use serde_json::json;
        // A string, a list, a list of non-objects, a list in a list, null, a number, an empty list,
        // wrong-typed fields: each counts as "no marker", and the status decides.
        for (status, body, want) in [
            (500, json!({"error": "boom"}), ErrorKind::Server),
            (400, json!([{"error": {"code": 400, "message": "bad"}}]), ErrorKind::BadRequest),
            (429, json!({"error": ["x"]}), ErrorKind::RateLimited),
            (429, json!({"error": [[{"code": "insufficient_quota"}]]}), ErrorKind::RateLimited),
            (503, json!({"error": null}), ErrorKind::Overloaded),
            (401, json!({"error": 7}), ErrorKind::Auth),
            (404, json!({"error": []}), ErrorKind::BadRequest),
            (500, json!("just text"), ErrorKind::Server),
            (500, json!([]), ErrorKind::Server),
            (429, json!({"error": {"code": 5, "type": ["x"], "message": 9}}), ErrorKind::RateLimited),
        ] {
            assert_eq!(classify_http(status, Some(&body), &[]).0, want, "{status} {body}");
        }
        // A list still carries its marker, whether it wraps the whole body (Google) or only the `error` field,
        // and a string error has no message to show.
        let google = json!([{"error": {"code": "insufficient_quota"}}]);
        assert_eq!(classify_http(429, Some(&google), &[]).0, ErrorKind::Billing);
        let wrapped = json!({"error": [{"type": "billing_error"}]});
        assert_eq!(classify_http(400, Some(&wrapped), &[]).0, ErrorKind::Billing);
        assert_eq!(error_field(Some(&json!({"error": "boom"})), "message"), None);
    }

    #[test]
    fn retry_after_is_ascii_digits_above_zero() {
        let retry = |v: &str| classify_http(429, None, &[("Retry-After".to_string(), v.to_string())]).1;
        assert_eq!(retry("30"), Some(30));
        assert_eq!(retry(" 7 "), Some(7));
        assert_eq!(retry("007"), Some(7));
        // `parse` alone would take "+5"; "0" means "use the default"; "\u{b2}" and "\u{663}" are digits to Unicode, not to HTTP.
        for bad in ["0", "00", "", "+5", "-1", "1.5", "5 s", "\u{b2}", "\u{663}", "Wed, 21 Oct 2026 07:28:00 GMT"] {
            assert_eq!(retry(bad), None, "{bad:?}");
        }
        assert_eq!(classify_http(429, None, &[]).1, None);
    }

    #[test]
    fn stream_errors_map_like_the_reference_table() {
        use ErrorKind::*;
        for (code, want) in [
            ("rate_limit_exceeded", RateLimited), ("rate_limit_error", RateLimited),
            ("server_is_overloaded", Overloaded), ("slow_down", Overloaded), ("overloaded_error", Overloaded),
            ("server_error", Server), ("api_error", Server), ("timeout_error", Server), ("vector_store_timeout", Server),
            ("insufficient_quota", Billing), ("credit_balance_exhausted", Billing),
            ("organization_usage_limit_exceeded", Billing), ("billing_error", Billing),
            ("project_spend_limit_exceeded", Billing), ("user_spend_limit_exceeded", Billing),
            ("invalid_prompt", Refusal), ("image_content_policy_violation", Refusal),
            ("content_policy_violation", Refusal), ("content_filter", Refusal),
            ("authentication_error", Auth), ("invalid_api_key", Auth), ("permission_error", Auth),
            ("invalid_request_error", BadRequest), ("context_length_exceeded", BadRequest),
            ("something_new", BadRequest), ("", BadRequest),
        ] {
            assert_eq!(stream_error_kind(code), want, "{code:?}");
        }
        // Only a temporary kind may fall back to a local model, and an unknown code never is one.
        for code in ["something_new", "invalid_prompt", "invalid_api_key", "insufficient_quota", "context_length_exceeded"] {
            assert!(!stream_error_kind(code).is_temporary(), "{code}");
        }
    }

    fn who(provider: &str, name: &str) -> Who {
        Who { provider: provider.into(), name: name.into() }
    }

    fn err_with(code: Option<&str>, retry: Option<u64>) -> AiError {
        AiError { code: code.map(str::to_string), retry_after: retry, ..AiError::new(ErrorKind::Billing) }
    }

    #[test]
    fn copy_matches_the_spec_table() {
        let anthropic = who("anthropic", "Anthropic");
        let openai = who("openai", "OpenAI");
        let lmstudio = who("lmstudio", "LM Studio");
        assert_eq!(
            error_copy(ErrorKind::Auth, &anthropic, None),
            Wording { text: "Your Anthropic key was rejected.".into(), action: Some(Action::OpenSettings) }
        );
        assert_eq!(error_copy(ErrorKind::Billing, &openai, Some(&err_with(Some("insufficient_quota"), None))).text, "Your OpenAI credit ran out.");
        assert_eq!(
            error_copy(ErrorKind::Billing, &openai, Some(&err_with(Some("project_spend_limit_exceeded"), None))).text,
            "Your OpenAI spend limit was reached."
        );
        assert!(matches!(
            error_copy(ErrorKind::Billing, &openai, None).action,
            Some(Action::OpenBilling { .. })
        ));
        assert_eq!(
            error_copy(ErrorKind::RateLimited, &anthropic, Some(&err_with(None, Some(20)))),
            Wording { text: "Claude is busy. Trying again in 20 s.".into(), action: Some(Action::Cancel) }
        );
        assert_eq!(error_copy(ErrorKind::Overloaded, &anthropic, None).text, "Claude is busy. Trying again in 20 s.");
        assert_eq!(
            error_copy(ErrorKind::Unreachable, &lmstudio, None),
            Wording { text: "Couldn't reach LM Studio. Is its server on?".into(), action: Some(Action::OpenGuide) }
        );
        assert_eq!(fallback_copy("anthropic", "qwen3.5:2b"), "Claude's busy right now, so Qwen answered instead.");
        assert_eq!(outdated_copy("Ollama").text, "Update Ollama to use it here.");
        let missing = AiError { code: Some(MISSING_KEY.into()), ..AiError::new(ErrorKind::Auth) };
        assert_eq!(error_copy(ErrorKind::Auth, &anthropic, Some(&missing)).text, "Your Anthropic key is missing.");
        assert_eq!(missing_model_copy("qwen3.5:2b", "Ollama").text, "qwen3.5:2b isn't on Ollama any more.");
        let bad = AiError { detail: Some("image exceeds 5 MB maximum".into()), ..AiError::new(ErrorKind::BadRequest) };
        assert_eq!(error_copy(ErrorKind::BadRequest, &anthropic, Some(&bad)).text, "Claude: image exceeds 5 MB maximum");
        assert_eq!(waking_copy("qwen3.5:2b"), "Waking up qwen3.5…");
        assert_eq!(TOO_LONG, "This chat got long, so I dropped the oldest messages.");
        assert_eq!(CANT_SEE, "This model can't see images. Pick one that can.");
    }

    #[test]
    fn empty_reply_and_file_copy() {
        assert_eq!(
            RAN_OUT_OF_ROOM,
            "The model ran out of room before answering. Try again, or pick a model without thinking mode."
        );
        assert_eq!(CUT_OFF, "The answer was cut off.");
        assert_eq!(HEIC, "HEIC photos aren't supported yet. Export it as JPEG or PNG.");
        assert_eq!(SCANNED_PDF_LINUX, "I can't read scanned PDFs on Linux yet. Try Claude or OpenAI, or paste the text.");
        assert!(scanned_pdf_copy().starts_with("I can't read"));
    }

    #[test]
    fn model_family_names() {
        assert_eq!(model_family("qwen3.5:2b"), "Qwen");
        assert_eq!(model_family("gemma-4-e2b"), "Gemma");
        assert_eq!(model_family("llama3"), "Llama");
        assert_eq!(model_family("3b-chat"), "3b-chat");
    }

    #[test]
    fn actions_serialize_for_the_island() {
        assert_eq!(serde_json::to_value(Action::OpenSettings).unwrap(), serde_json::json!({"kind": "openSettings"}));
        assert_eq!(
            serde_json::to_value(Action::OpenBilling { url: "https://x".into() }).unwrap(),
            serde_json::json!({"kind": "openBilling", "url": "https://x"})
        );
    }
}
