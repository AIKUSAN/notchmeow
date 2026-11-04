// Finding local model servers (spec §2). Only this computer (127.0.0.1) is
// checked on its own, every probe in parallel with a 300 ms limit; a network
// server is only ever one the user typed in. Runs at launch, when the picker or
// the AI settings open, and when Auto needs a local model — never on a timer.

use std::path::PathBuf;
use std::time::Duration;

use serde::Serialize;
use serde_json::{json, Value};

use crate::ai::catalog;
use crate::ai::provider::{ModelInfo, Placement};

/// Shown for anything that answers in the OpenAI format but isn't who its port says.
pub const UNKNOWN_SERVER: &str = "Local server (OpenAI-compatible)";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum ServerStatus {
    Running,
    Off,
    NotInstalled,
    /// Ollama answers but has no OpenAI-compatible API yet.
    Outdated,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Server {
    /// ollama, lmstudio, llamacpp, jan or custom.
    pub provider: String,
    pub name: String,
    pub base_url: String,
    pub host: String,
    pub placement: Placement,
    pub status: ServerStatus,
    pub models: Vec<ModelInfo>,
    /// Plain http to another computer: "unencrypted on your network".
    pub unencrypted: bool,
}

#[derive(Clone, PartialEq)]
pub struct Probe {
    pub provider: String,
    pub base_url: String,
    pub key: Option<String>,
}

/// By hand, like `Endpoint`'s: a derived `Debug` would print the key.
impl std::fmt::Debug for Probe {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Probe")
            .field("provider", &self.provider)
            .field("base_url", &self.base_url)
            .field("key", &self.key.as_ref().map(|_| "<redacted>"))
            .finish()
    }
}

/// The four servers checked on 127.0.0.1.
pub fn localhost_probes() -> Vec<Probe> {
    catalog::LOCAL_SERVERS
        .iter()
        .map(|id| Probe { provider: id.to_string(), base_url: catalog::get(id).unwrap().base_url.unwrap().to_string(), key: None })
        .collect()
}

/// What settings.json and the webview may hold for the server the user added: an http(s) URL
/// with a host, normalised (no trailing `/` or `/v1`) and without anything secret: a typed
/// `user:pass@`, a `?key=…` query or a `#fragment` are dropped, because a key belongs in the
/// key field (the OS keychain), never in a URL that is saved and shown. `None` for anything
/// that isn't such a URL.
pub fn clean_server_url(url: &str) -> Option<String> {
    let mut parsed = reqwest::Url::parse(url.trim()).ok()?;
    if !matches!(parsed.scheme(), "http" | "https") || parsed.host_str().is_none() {
        return None;
    }
    let _ = parsed.set_username("");
    let _ = parsed.set_password(None);
    parsed.set_query(None);
    parsed.set_fragment(None);
    let text = parsed.as_str().trim_end_matches('/');
    let text = text.strip_suffix("/v1").unwrap_or(text);
    Some(text.trim_end_matches('/').to_string())
}

/// The server the user added, as `clean_server_url` spells it. `None` for anything that
/// isn't an http(s) URL with a host.
pub fn custom_probe(url: &str, key: Option<String>) -> Option<Probe> {
    Some(Probe { provider: "custom".into(), base_url: clean_server_url(url)?, key })
}

/// Probes every server in parallel. Results keep the order of `probes`.
pub async fn discover(probes: Vec<Probe>, timeout: Duration) -> Vec<Server> {
    join(probes.into_iter().map(|p| tokio::spawn(probe(p, timeout))).collect()).await
}

async fn join(handles: Vec<tokio::task::JoinHandle<Server>>) -> Vec<Server> {
    let mut out = Vec::new();
    for h in handles {
        if let Ok(server) = h.await {
            out.push(server);
        }
    }
    out
}

/// Two phases that start together: the built-in localhost probes with `local`, the server the user added
/// (`custom`) with `added`, so a sleepy LAN host isn't marked off. Returns the localhost results as soon as
/// that phase ends, and the added server's still running as a handle; both keep the order of `probes`.
pub async fn discover_split(
    probes: Vec<Probe>,
    local: Duration,
    added: Duration,
) -> (Vec<Server>, tokio::task::JoinHandle<Vec<Server>>) {
    let (far, near): (Vec<_>, Vec<_>) = probes.into_iter().partition(|p| p.provider == "custom");
    let far = tokio::spawn(join(far.into_iter().map(|p| tokio::spawn(probe(p, added))).collect()));
    let near = join(near.into_iter().map(|p| tokio::spawn(probe(p, local))).collect()).await;
    (near, far)
}

/// `Some((status, json))` when the server answered at all; `None` when the
/// connection failed or timed out.
async fn get(client: &reqwest::Client, probe: &Probe, path: &str) -> Option<(u16, Value)> {
    let mut req = client.get(format!("{}{path}", probe.base_url));
    if let Some(k) = probe.key.as_ref().filter(|k| !k.is_empty()) {
        req = req.bearer_auth(k);
    }
    let resp = req.send().await.ok()?;
    let status = resp.status().as_u16();
    Some((status, resp.json().await.unwrap_or(Value::Null)))
}

fn model_list(body: &Value) -> Option<Vec<ModelInfo>> {
    let data = body.get("data")?.as_array()?;
    Some(data.iter().filter_map(|m| m["id"].as_str()).map(ModelInfo::named).collect())
}

/// Host, placement and the "unencrypted" flag of a server URL.
pub fn describe(provider: &str, base_url: &str) -> (String, Placement, bool) {
    let host = reqwest::Url::parse(base_url).ok().and_then(|u| u.host_str().map(str::to_string)).unwrap_or_default();
    let placement = catalog::placement_of(provider, Some(&host));
    let unencrypted = placement == Placement::Network && base_url.starts_with("http://");
    (host, placement, unencrypted)
}

async fn probe(p: Probe, timeout: Duration) -> Server {
    let (host, placement, unencrypted) = describe(&p.provider, &p.base_url);
    let catalog_name = catalog::get(&p.provider).map(|d| d.name).unwrap_or("Local server");
    let mut server = Server {
        provider: p.provider.clone(),
        name: if p.provider == "custom" { host.clone() } else { catalog_name.to_string() },
        base_url: p.base_url.clone(),
        host,
        placement,
        status: ServerStatus::Off,
        models: Vec::new(),
        unencrypted,
    };
    let client = reqwest::Client::builder().timeout(timeout).no_proxy().build().unwrap_or_default();

    // Who is this? The port's own check endpoint (catalog `probePath`); a
    // connection failure ends it here.
    let check = catalog::get(&p.provider).and_then(|d| d.probe_path).filter(|path| *path != "/v1/models");
    let identified = match (p.provider.as_str(), check) {
        ("ollama", Some(path)) => match get(&client, &p, path).await {
            None => return finish(server),
            Some((200, v)) => v.get("version").is_some(),
            Some(_) => false,
        },
        (_, Some(path)) => match get(&client, &p, path).await {
            None => return finish(server),
            Some((status, _)) => status == 200,
        },
        _ => true,
    };
    let body = match get(&client, &p, "/v1/models").await {
        None => return finish(server),
        Some((200, body)) => body,
        Some((404, _)) if identified && p.provider == "ollama" => {
            server.status = ServerStatus::Outdated;
            return server;
        }
        Some(_) => Value::Null,
    };
    let Some(models) = model_list(&body) else {
        // llama.cpp says it is healthy but has no model list yet: still loading.
        if identified && p.provider == "llamacpp" {
            server.status = ServerStatus::Running;
        }
        return finish(server);
    };
    // mistral.rs also takes port 1234; LM Studio's list says `organization_owner` or nothing.
    let lmstudio_like = p.provider != "lmstudio"
        || body["data"]
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(|m| m.get("owned_by").and_then(Value::as_str))
            .all(|o| o == "organization_owner");
    if !(identified && lmstudio_like) && p.provider != "custom" {
        server.name = UNKNOWN_SERVER.to_string();
    }
    server.status = ServerStatus::Running;
    server.models = catalog::filter_models(&p.provider, models);
    server
}

/// A server that didn't answer is "Server off", or "Not installed" when nothing
/// of it is on this computer either.
fn finish(mut server: Server) -> Server {
    if server.status == ServerStatus::Off && !installed(&server.provider) {
        server.status = ServerStatus::NotInstalled;
    }
    server
}

/// Best effort: Jan and custom servers can't be told apart from "off", so they count as installed.
fn installed(provider: &str) -> bool {
    let home: PathBuf = crate::platform::home_dir();
    match provider {
        "ollama" => crate::platform::find_on_path("ollama").is_some(),
        "lmstudio" => crate::platform::find_on_path("lms").is_some() || home.join(".lmstudio").exists(),
        "llamacpp" => crate::platform::find_on_path("llama-server").is_some(),
        _ => true,
    }
}

/// What a local server says about one model: whether it reads images, and the context it runs at.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Details {
    pub vision: bool,
    /// `None` when the server reports nothing usable; the budget then counts 4,096 tokens.
    pub context_tokens: Option<u64>,
}

/// Servers run a model at the context it is loaded with, not the one it was trained for, so the
/// runtime value wins; the trained maximum is capped at the default, since a server that
/// reports no runtime value runs at about that. A value of 0 or less is no value at all.
pub fn context_tokens(runtime: Option<i64>, trained: Option<i64>) -> Option<u64> {
    let positive = |v: Option<i64>| v.filter(|n| *n > 0).map(|n| n as u64);
    positive(runtime).or_else(|| positive(trained).map(|n| n.min(catalog::DEFAULT_LOCAL_CONTEXT_TOKENS)))
}

/// `num_ctx` from the text of Ollama's `parameters` (one `name   value` per line).
fn ollama_num_ctx(parameters: &str) -> Option<i64> {
    parameters.lines().find_map(|line| {
        let mut words = line.split_whitespace();
        (words.next() == Some("num_ctx")).then(|| words.next()?.parse().ok()).flatten()
    })
}

/// The trained maximum from Ollama's `model_info`: `<general.architecture>.context_length`.
fn ollama_trained_context(info: &Value) -> Option<i64> {
    let arch = info["general.architecture"].as_str()?;
    info[format!("{arch}.context_length")].as_i64()
}

/// Ollama's `/api/show` capabilities and context, LM Studio's model type and context. Anything
/// else, or no answer within a second, is text only with an unknown context.
pub async fn details(server: &Server, model: &str) -> Details {
    let client = reqwest::Client::builder().timeout(Duration::from_secs(1)).no_proxy().build().unwrap_or_default();
    let base = server.base_url.trim_end_matches('/');
    match server.provider.as_str() {
        "ollama" => {
            let Ok(resp) = client.post(format!("{base}/api/show")).json(&json!({ "model": model })).send().await else {
                return Details::default();
            };
            let body: Value = resp.json().await.unwrap_or(Value::Null);
            Details {
                vision: body["capabilities"].as_array().is_some_and(|c| c.iter().any(|v| v == "vision")),
                context_tokens: context_tokens(
                    body["parameters"].as_str().and_then(ollama_num_ctx),
                    ollama_trained_context(&body["model_info"]),
                ),
            }
        }
        "lmstudio" => {
            // Ids look like `publisher/model`, so match in the list instead of building a per-model URL.
            let Ok(resp) = client.get(format!("{base}/api/v0/models")).send().await else {
                return Details::default();
            };
            let body: Value = resp.json().await.unwrap_or(Value::Null);
            let Some(row) = body["data"].as_array().and_then(|m| m.iter().find(|e| e["id"] == model)) else {
                return Details::default();
            };
            Details {
                vision: row["type"] == "vlm",
                context_tokens: context_tokens(row["loaded_context_length"].as_i64(), row["max_context_length"].as_i64()),
            }
        }
        _ => Details::default(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ai::testkit::FakeServer;
    use std::time::Instant;

    fn closed_port() -> String {
        let port = std::net::TcpListener::bind("127.0.0.1:0").unwrap().local_addr().unwrap().port();
        format!("http://127.0.0.1:{port}")
    }

    fn probe(provider: &str, base: &str) -> Probe {
        Probe { provider: provider.into(), base_url: base.into(), key: None }
    }

    const T: Duration = Duration::from_millis(catalog::PROBE_MS);
    const ADDED_T: Duration = Duration::from_millis(catalog::ADDED_PROBE_MS);

    #[tokio::test]
    async fn personas_are_identified() {
        let ollama = FakeServer::start(&["--persona", "ollama"]);
        let lmstudio = FakeServer::start(&["--persona", "lmstudio"]);
        let llamacpp = FakeServer::start(&["--persona", "llamacpp"]);
        let jan = FakeServer::start(&["--persona", "jan"]);
        let servers = discover(
            vec![
                probe("ollama", &ollama.base),
                probe("lmstudio", &lmstudio.base),
                probe("llamacpp", &llamacpp.base),
                probe("jan", &jan.base),
            ],
            T,
        )
        .await;
        let names: Vec<&str> = servers.iter().map(|s| s.name.as_str()).collect();
        assert_eq!(names, ["Ollama", "LM Studio", "llama.cpp", "Jan"]);
        for s in &servers {
            assert_eq!(s.status, ServerStatus::Running, "{}", s.name);
            assert_eq!(s.models.iter().map(|m| m.id.as_str()).collect::<Vec<_>>(), ["llama3.2"], "{}", s.name);
            assert_eq!(s.placement, Placement::Local);
        }
        // Probes never carry an Origin header.
        assert!(ollama.requests().iter().all(|r| r["origin"].is_null()));
    }

    #[tokio::test]
    async fn the_wrong_server_on_a_known_port_is_a_local_server() {
        let generic = FakeServer::start(&[]);
        let servers = discover(vec![probe("ollama", &generic.base), probe("llamacpp", &generic.base)], T).await;
        for s in servers {
            assert_eq!((s.name.as_str(), s.status), (UNKNOWN_SERVER, ServerStatus::Running));
        }
    }

    #[tokio::test]
    async fn nothing_running_finishes_fast() {
        let probes = (0..4).map(|_| probe("jan", &closed_port())).collect();
        let started = Instant::now();
        let servers = discover(probes, T).await;
        assert!(started.elapsed() < Duration::from_millis(400), "took {:?}", started.elapsed());
        assert!(servers.iter().all(|s| s.status != ServerStatus::Running));
    }

    #[tokio::test]
    async fn a_sleepy_added_server_is_ready_and_localhost_does_not_wait_for_it() {
        let local = FakeServer::start(&["--persona", "ollama"]);
        let lan = FakeServer::start(&["--fail", "slow-models", "--delay", "1"]); // answers after 1 s
        let probes = vec![probe("ollama", &local.base), probe("custom", &lan.base)];
        let started = Instant::now();
        let (near, far) = discover_split(probes, T, ADDED_T).await;
        assert!(started.elapsed() < Duration::from_millis(900), "localhost waited for the slow server: {:?}", started.elapsed());
        assert_eq!(near.iter().map(|s| s.provider.as_str()).collect::<Vec<_>>(), ["ollama"], "the local phase holds only the localhost probe");
        let far = far.await.unwrap();
        assert!(started.elapsed() >= Duration::from_secs(1), "the added server was not waited for");
        assert_eq!((far[0].provider.as_str(), far[0].status), ("custom", ServerStatus::Running));
        // The 0.3 s probe alone would have marked it off.
        assert_ne!(discover(vec![probe("custom", &lan.base)], T).await[0].status, ServerStatus::Running);
    }

    #[tokio::test]
    async fn a_silent_port_costs_one_probe_timeout() {
        // Accepts the connection, never answers.
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        let started = Instant::now();
        let servers = discover(vec![probe("ollama", &base)], T).await;
        assert!(started.elapsed() < Duration::from_millis(600), "took {:?}", started.elapsed());
        assert_ne!(servers[0].status, ServerStatus::Running);
        drop(listener);
    }

    #[test]
    fn custom_urls_are_normalised() {
        let p = custom_probe(" http://studio-pc:11434/v1/ ", None).unwrap();
        assert_eq!(p.base_url, "http://studio-pc:11434");
        assert!(custom_probe("ftp://x", None).is_none());
        assert!(custom_probe("not a url", None).is_none());
    }

    #[test]
    fn a_typed_password_never_survives_into_the_url() {
        for typed in [
            "http://me:hunter2@studio-pc:11434",
            "http://me:hunter2@studio-pc:11434/v1/?api_key=abc#frag",
            "http://:hunter2@studio-pc:11434/",
            "https://me@studio-pc:11434/v1",
        ] {
            let clean = clean_server_url(typed).unwrap();
            assert!(!clean.contains("hunter2") && !clean.contains("me@") && !clean.contains("abc"), "{typed} → {clean}");
            assert!(clean.starts_with("http") && clean.contains("studio-pc:11434"), "{clean}");
            assert_eq!(custom_probe(typed, None).unwrap().base_url, clean);
        }
        assert_eq!(clean_server_url("http://me:pw@studio-pc:11434/v1/").as_deref(), Some("http://studio-pc:11434"));
        assert_eq!(clean_server_url("http://host/proxy/ollama/").as_deref(), Some("http://host/proxy/ollama"));
        assert_eq!(clean_server_url("not a url"), None);
    }

    #[test]
    fn a_probe_never_prints_its_key() {
        let p = custom_probe("http://studio-pc:11434", Some("sk-live-SECRET".into())).unwrap();
        let printed = format!("{p:?} {p:#?}");
        assert!(!printed.contains("sk-live-SECRET") && printed.contains("<redacted>"), "{printed}");
    }

    #[tokio::test]
    async fn a_custom_server_on_this_computer_is_local() {
        let fake = FakeServer::start(&[]);
        let local = discover(vec![custom_probe(&fake.base, None).unwrap()], T).await;
        assert_eq!((local[0].placement, local[0].unencrypted, local[0].status), (Placement::Local, false, ServerStatus::Running));
        assert_eq!(local[0].name, "127.0.0.1");
    }

    #[tokio::test]
    async fn a_server_url_with_a_password_reaches_the_webview_without_it() {
        let fake = FakeServer::start(&[]);
        let typed = format!("http://me:hunter2@{}", fake.base.trim_start_matches("http://"));
        let servers = discover(vec![custom_probe(&typed, None).unwrap()], T).await;
        assert_eq!(servers[0].status, ServerStatus::Running);
        // `Server` is what `ai_discover` sends to the webview.
        let sent = serde_json::to_string(&servers).unwrap();
        assert!(!sent.contains("hunter2") && !sent.contains("me:"), "{sent}");
    }

    #[tokio::test]
    async fn an_empty_key_sends_no_authorization_header() {
        use std::io::{Read, Write};
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        let seen = std::thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut buf = [0u8; 4096];
            let n = stream.read(&mut buf).unwrap();
            let _ = stream.write_all(b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
            String::from_utf8_lossy(&buf[..n]).to_ascii_lowercase()
        });
        let probe = Probe { provider: "custom".into(), base_url: base, key: Some(String::new()) };
        discover(vec![probe], ADDED_T).await;
        let request = seen.join().unwrap();
        assert!(request.starts_with("get /v1/models"), "{request}");
        assert!(!request.contains("authorization"), "an empty key must not become `Authorization: Bearer `: {request}");
    }

    #[test]
    fn a_network_server_is_labelled_and_plain_http_is_flagged() {
        assert_eq!(describe("custom", "http://studio-pc:11434"), ("studio-pc".into(), Placement::Network, true));
        assert_eq!(describe("custom", "https://studio-pc"), ("studio-pc".into(), Placement::Network, false));
        assert_eq!(describe("custom", "http://localhost:8080"), ("localhost".into(), Placement::Local, false));
        assert_eq!(describe("ollama", "http://127.0.0.1:11434"), ("127.0.0.1".into(), Placement::Local, false));
    }

    fn server(provider: &str, base: &str) -> Server {
        let (host, placement, unencrypted) = describe(provider, base);
        Server {
            provider: provider.into(),
            name: "Test".into(),
            base_url: base.into(),
            host,
            placement,
            status: ServerStatus::Running,
            models: vec![],
            unencrypted,
        }
    }

    #[tokio::test]
    async fn vision_is_read_from_ollama_capabilities() {
        let base = crate::ai::testkit::canned_server(200, "application/json", r#"{"capabilities":["completion","vision"]}"#);
        assert!(details(&server("ollama", &base), "llava").await.vision);
        let base = crate::ai::testkit::canned_server(200, "application/json", r#"{"capabilities":["completion"]}"#);
        assert!(!details(&server("ollama", &base), "llama3.2").await.vision);
    }

    #[tokio::test]
    async fn vision_is_read_from_the_lm_studio_model_list() {
        let list = r#"{"data":[{"id":"publisher/some-vl","type":"vlm"},{"id":"publisher/plain","type":"llm"}]}"#;
        let base = crate::ai::testkit::canned_server(200, "application/json", list);
        assert!(details(&server("lmstudio", &base), "publisher/some-vl").await.vision);
        assert!(!details(&server("lmstudio", &base), "publisher/plain").await.vision);
        assert!(!details(&server("lmstudio", &base), "publisher/missing").await.vision);
    }

    #[tokio::test]
    async fn vision_is_false_when_the_server_refuses() {
        assert!(!details(&server("ollama", &closed_port()), "llava").await.vision);
    }

    #[test]
    fn a_runtime_context_wins_and_a_trained_one_is_capped_at_the_default() {
        assert_eq!(context_tokens(Some(16_384), Some(131_072)), Some(16_384), "the loaded context, not the trained maximum");
        assert_eq!(context_tokens(None, Some(131_072)), Some(4_096), "capped");
        assert_eq!(context_tokens(None, Some(2_048)), Some(2_048), "a small model keeps its own");
        assert_eq!(context_tokens(None, None), None);
        // 0 or less is "unknown", for either value.
        assert_eq!(context_tokens(Some(0), Some(131_072)), Some(4_096));
        assert_eq!(context_tokens(Some(-1), Some(0)), None);
        assert_eq!(ollama_num_ctx("stop \"<|eot|>\"\nnum_ctx                        8192\nnum_predict 64"), Some(8192));
        assert_eq!(ollama_num_ctx("stop \"num_ctx 5\""), None);
    }

    async fn ctx_of(persona: &str, provider: &str, model: &str) -> Option<u64> {
        let fake = FakeServer::start(&["--persona", persona]);
        details(&server(provider, &fake.base), model).await.context_tokens
    }

    #[tokio::test]
    async fn ollama_reports_its_context_through_api_show() {
        for (model, want) in [
            ("ctx-runtime", Some(8_192)),
            ("ctx-trained-big", Some(4_096)),
            ("ctx-trained-small", Some(2_048)),
            ("ctx-none", None),
            ("ctx-zero", None),
            ("not-a-model", None),
        ] {
            assert_eq!(ctx_of("ollama-ctx", "ollama", model).await, want, "{model}");
        }
    }

    #[tokio::test]
    async fn lm_studio_reports_its_context_through_the_model_list() {
        for (model, want) in [
            ("lm-loaded", Some(16_384)),
            ("lm-max-big", Some(4_096)),
            ("lm-max-small", Some(2_048)),
            ("lm-none", None),
            ("lm-zero", None),
            ("not-a-model", None),
        ] {
            assert_eq!(ctx_of("lmstudio-ctx", "lmstudio", model).await, want, "{model}");
        }
    }
}
