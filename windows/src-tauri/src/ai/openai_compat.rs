// OpenAI-compatible chat completions: Google's OpenAI endpoint, Ollama, LM Studio,
// llama.cpp, Jan and any server the user adds. Sends `max_tokens` (not
// `max_completion_tokens`) and never `tool_choice`: Ollama ignores both.
// `<think>` blocks are hidden by the sse aggregator.

use std::time::Duration;

use serde_json::{json, Value};

use crate::ai::catalog;
use crate::ai::errors;
use crate::ai::provider::{
    file_label, file_text, http_client as client, AiError, Aggregate, BoxFuture, ChatChunk, ChatRequest, Endpoint,
    ErrorKind, ModelInfo, ModelProvider, Part, Placement, Role,
};
use crate::ai::sse::{self, Format};

pub struct OpenAICompat {
    pub endpoint: Endpoint,
}

impl OpenAICompat {
    pub fn new(endpoint: Endpoint) -> Self {
        OpenAICompat { endpoint }
    }

    fn url(&self, chat: bool) -> String {
        let def = catalog::get(&self.endpoint.provider).or_else(|| catalog::get("custom")).unwrap();
        let path = if chat { def.chat_path } else { def.models_path };
        format!("{}{}", self.endpoint.base_url.trim_end_matches('/'), path.unwrap_or(""))
    }

    fn authed(&self, req: reqwest::RequestBuilder) -> reqwest::RequestBuilder {
        match self.endpoint.key.as_deref().filter(|k| !k.is_empty()) {
            Some(k) => req.bearer_auth(k),
            None => req,
        }
    }

    pub fn body(request: &ChatRequest) -> Value {
        let mut messages = vec![json!({ "role": "system", "content": request.system })];
        for m in &request.messages {
            let role = if m.role == Role::User { "user" } else { "assistant" };
            if m.parts.iter().any(|p| matches!(p, Part::Image { .. })) {
                let mut content = Vec::new();
                for p in &m.parts {
                    match p {
                        Part::Text(t) => content.push(json!({ "type": "text", "text": t })),
                        Part::FileText { name, text } => content.push(json!({ "type": "text", "text": file_text(name, text) })),
                        Part::Pdf { name, .. } => content.push(json!({ "type": "text", "text": file_label(name) })),
                        Part::Image { name, mime, base64 } => {
                            content.push(json!({ "type": "text", "text": file_label(name) }));
                            content.push(json!({ "type": "image_url", "image_url": { "url": format!("data:{mime};base64,{base64}") } }));
                        }
                    }
                }
                messages.push(json!({ "role": role, "content": content }));
            } else {
                messages.push(json!({ "role": role, "content": m.plain_text() }));
            }
        }
        json!({
            "model": request.model,
            "messages": messages,
            "stream": true,
            "max_tokens": request.max_tokens,
        })
    }
}

impl ModelProvider for OpenAICompat {
    fn id(&self) -> &str {
        &self.endpoint.provider
    }

    fn display_name(&self) -> &str {
        &self.endpoint.name
    }

    fn placement(&self) -> Placement {
        self.endpoint.placement
    }

    fn list_models(&self) -> BoxFuture<'_, Result<Vec<ModelInfo>, AiError>> {
        Box::pin(async move {
            let client = client(&self.endpoint, Some(Duration::from_secs(10)));
            let response = self.authed(client.get(self.url(false))).send().await.map_err(|e| errors::from_transport(&e))?;
            if !response.status().is_success() {
                return Err(errors::from_response(response).await);
            }
            let body: Value = response.json().await.map_err(|_| AiError::new(ErrorKind::Server))?;
            let models = body["data"]
                .as_array()
                .into_iter()
                .flatten()
                .filter_map(|m| m["id"].as_str())
                .map(|id| ModelInfo::named(id.strip_prefix("models/").unwrap_or(id)))
                .collect();
            Ok(catalog::filter_models(&self.endpoint.provider, models))
        })
    }

    fn stream<'a>(
        &'a self,
        request: &'a ChatRequest,
        sink: &'a mut (dyn FnMut(ChatChunk) + Send),
    ) -> BoxFuture<'a, Result<Aggregate, AiError>> {
        Box::pin(async move {
            let client = client(&self.endpoint, None);
            let req = self.authed(client.post(self.url(true))).json(&Self::body(request));
            let t = self.endpoint.timeouts;
            sse::stream_request(req, Format::OpenAIChat, t.first_token, t.idle, sink).await
        })
    }

    /// Ollama loads a model when asked to generate nothing.
    fn prewarm<'a>(&'a self, model: &'a str) -> BoxFuture<'a, ()> {
        Box::pin(async move {
            if self.endpoint.provider != "ollama" {
                return;
            }
            let client = client(&self.endpoint, Some(Duration::from_secs(120)));
            let url = format!("{}/api/generate", self.endpoint.base_url.trim_end_matches('/'));
            let _ = client.post(url).json(&json!({ "model": model })).send().await;
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ai::provider::{Message, Timeouts};
    use crate::ai::testkit::FakeServer;

    fn endpoint(provider: &str, base: &str) -> Endpoint {
        Endpoint {
            provider: provider.into(),
            name: "Test".into(),
            base_url: base.into(),
            key: None,
            placement: Placement::Local,
            timeouts: Timeouts::for_placement(Placement::Local),
        }
    }

    fn request(text: &str) -> ChatRequest {
        ChatRequest {
            model: "llama3.2".into(),
            system: "sys".into(),
            messages: vec![Message { role: Role::User, parts: vec![Part::Text(text.into())] }],
            tools: vec![],
            response_format: None,
            // Any value: the provider must put the request's own limit on the wire.
            max_tokens: 1234,
        }
    }

    async fn run(p: &OpenAICompat, req: &ChatRequest) -> (Result<Aggregate, AiError>, String) {
        let mut shown = String::new();
        let mut sink = |c: ChatChunk| {
            if let ChatChunk::Text(t) = c {
                shown.push_str(&t);
            }
        };
        let r = p.stream(req, &mut sink).await;
        (r, shown)
    }

    #[tokio::test]
    async fn streams_and_hides_think_blocks() {
        let fake = FakeServer::start(&[]);
        let p = OpenAICompat::new(endpoint("ollama", &fake.base));
        let (r, shown) = run(&p, &request("hi")).await;
        let agg = r.unwrap();
        assert_eq!(agg.error, None);
        assert!(!agg.text.contains("<think>") && agg.text.starts_with("## Answer"), "{:?}", agg.text);
        assert_eq!(shown, agg.text);
    }

    #[tokio::test]
    async fn request_sends_max_tokens_never_tool_choice_and_no_origin() {
        let fake = FakeServer::start(&[]);
        let p = OpenAICompat::new(endpoint("lmstudio", &fake.base));
        let _ = run(&p, &request("hi")).await;
        let log = fake.requests();
        let chat = log.iter().find(|r| r["path"] == "/v1/chat/completions").unwrap();
        assert_eq!(chat["body"]["max_tokens"], 1234, "the request's own limit, as given");
        assert!(chat["body"].get("max_completion_tokens").is_none());
        assert!(chat["body"].get("tool_choice").is_none());
        assert_eq!(chat["body"]["stream"], true);
        assert_eq!(chat["body"]["messages"][0]["role"], "system");
        assert!(chat["origin"].is_null(), "Ollama refuses http://tauri.localhost; we must send no Origin");
    }

    #[tokio::test]
    async fn cut_stream_keeps_partial_text_as_interrupted() {
        let fake = FakeServer::start(&["--fail", "cut"]);
        let p = OpenAICompat::new(endpoint("ollama", &fake.base));
        let agg = run(&p, &request("hi")).await.0.unwrap();
        assert_eq!(agg.error, Some(ErrorKind::Interrupted));
        assert_eq!(agg.finish, None);
    }

    #[tokio::test]
    async fn http_errors_are_classified() {
        let fake = FakeServer::start(&["--fail", "429"]);
        let p = OpenAICompat::new(endpoint("ollama", &fake.base));
        let err = run(&p, &request("hi")).await.0.unwrap_err();
        assert_eq!((err.kind, err.retry_after, err.status), (ErrorKind::RateLimited, Some(2), Some(429)));

        let fake = FakeServer::start(&["--fail", "500"]);
        let p = OpenAICompat::new(endpoint("ollama", &fake.base));
        assert_eq!(run(&p, &request("hi")).await.0.unwrap_err().kind, ErrorKind::Server);
    }

    #[tokio::test]
    async fn no_first_token_in_time_is_a_timeout() {
        let fake = FakeServer::start(&["--fail", "slow-first-token", "--delay", "2"]);
        let mut e = endpoint("ollama", &fake.base);
        e.timeouts.first_token = Duration::from_millis(400);
        let p = OpenAICompat::new(e);
        assert_eq!(run(&p, &request("hi")).await.0.unwrap_err().kind, ErrorKind::Timeout);
    }

    /// A reasoning model thinks for longer than the 60 s first-token limit before it says a word:
    /// its reasoning deltas are output, so the limit stops counting. Simulated clock, no real wait.
    #[tokio::test(start_paused = true)]
    async fn a_model_that_only_reasons_for_61_seconds_is_not_timed_out() {
        let secs = Duration::from_secs;
        let delta = |d: Value| json!({ "choices": [{ "index": 0, "delta": d }] }).to_string();
        let script = vec![
            (secs(1), delta(json!({ "role": "assistant", "content": "", "reasoning_content": "hmm" }))),
            (secs(20), delta(json!({ "reasoning": "still thinking" }))),
            (secs(20), delta(json!({ "reasoning_content": "almost" }))),
            (secs(20), delta(json!({ "content": "<think>" }))),
            (secs(1), delta(json!({ "content": "more</think>Hello" }))),
            (secs(0), json!({ "choices": [{ "index": 0, "delta": {}, "finish_reason": "stop" }] }).to_string()),
            (secs(0), "[DONE]".to_string()),
        ];
        let base = crate::ai::testkit::paced_sse_server(script).await;
        let p = OpenAICompat::new(endpoint("ollama", &base));
        let (r, shown) = run(&p, &request("hi")).await;
        let agg = r.expect("not timed out");
        assert_eq!((agg.error, agg.finish), (None, Some(crate::ai::provider::Finish::Stop)));
        assert_eq!(shown, "Hello", "the reasoning itself is never shown");
    }

    #[tokio::test(start_paused = true)]
    async fn silence_past_the_first_token_limit_still_times_out() {
        // The control for the test above: the same clock, but nothing at all for 61 s.
        let script = vec![(Duration::from_secs(61), "[DONE]".to_string())];
        let base = crate::ai::testkit::paced_sse_server(script).await;
        let p = OpenAICompat::new(endpoint("ollama", &base));
        assert_eq!(run(&p, &request("hi")).await.0.unwrap_err().kind, ErrorKind::Timeout);
    }

    #[tokio::test]
    async fn refused_connection_is_unreachable() {
        let port = std::net::TcpListener::bind("127.0.0.1:0").unwrap().local_addr().unwrap().port();
        let p = OpenAICompat::new(endpoint("ollama", &format!("http://127.0.0.1:{port}")));
        assert_eq!(run(&p, &request("hi")).await.0.unwrap_err().kind, ErrorKind::Unreachable);
    }

    #[tokio::test]
    async fn lists_models_without_embeddings() {
        let fake = FakeServer::start(&[]);
        let p = OpenAICompat::new(endpoint("ollama", &fake.base));
        let ids: Vec<String> = p.list_models().await.unwrap().into_iter().map(|m| m.id).collect();
        assert_eq!(ids, ["llama3.2"]);
    }

    #[test]
    fn images_become_content_parts() {
        let req = ChatRequest {
            messages: vec![Message {
                role: Role::User,
                parts: vec![
                    Part::Image { name: "cat.png".into(), mime: "image/png".into(), base64: "AAAA".into() },
                    Part::Text("what is this?".into()),
                ],
            }],
            ..request("")
        };
        let body = OpenAICompat::body(&req);
        let content = &body["messages"][1]["content"];
        assert_eq!(content[1]["image_url"]["url"], "data:image/png;base64,AAAA");
        assert_eq!(content[2]["text"], "what is this?");
        let plain = OpenAICompat::body(&request("hello"));
        assert_eq!(plain["messages"][1]["content"], "hello");
    }

    #[test]
    fn a_missing_or_empty_key_sends_no_authorization_header() {
        for key in [None, Some(String::new())] {
            let provider = OpenAICompat::new(Endpoint { key, ..endpoint("custom", "http://127.0.0.1:1") });
            let req = provider.authed(reqwest::Client::new().get("http://127.0.0.1:1/v1/models")).build().unwrap();
            assert!(req.headers().get("authorization").is_none(), "{:?}", req.headers());
        }
    }
}
