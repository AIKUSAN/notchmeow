// Claude through Anthropic's Messages API: the integration that lived in
// claude.rs, now streaming. Server-side web search with cited sources, PDFs as
// document blocks, images as image blocks. The key never leaves Rust.

use std::time::Duration;

use serde_json::{json, Value};

use crate::ai::catalog;
use crate::ai::errors;
use crate::ai::provider::{
    file_label, file_text, http_client as client, AiError, Aggregate, BoxFuture, ChatChunk, ChatRequest, Endpoint, ErrorKind, ModelInfo,
    ModelProvider, Part, Placement, Role,
};
use crate::ai::sse::{self, Format};

pub const ANTHROPIC_VERSION: &str = "2023-06-01";
/// Server-side fallback: on a policy decline the API retries the same request on
/// a fallback model inside the same call, so the island never shows a dead end.
pub const FALLBACK_BETA: &str = "server-side-fallback-2026-07-01";

pub struct Anthropic {
    pub endpoint: Endpoint,
}

impl Anthropic {
    pub fn new(endpoint: Endpoint) -> Self {
        Anthropic { endpoint }
    }

    fn headers(&self, req: reqwest::RequestBuilder) -> reqwest::RequestBuilder {
        let req = match self.endpoint.key.as_deref().filter(|k| !k.is_empty()) {
            Some(k) => req.header("x-api-key", k),
            None => req,
        };
        req.header("anthropic-version", ANTHROPIC_VERSION)
    }

    pub fn body(request: &ChatRequest) -> Value {
        let messages: Vec<Value> = request
            .messages
            .iter()
            .map(|m| {
                let mut content = Vec::new();
                for p in &m.parts {
                    match p {
                        Part::Text(t) => content.push(json!({ "type": "text", "text": t })),
                        Part::FileText { name, text } => content.push(json!({ "type": "text", "text": file_text(name, text) })),
                        Part::Pdf { name, base64 } => {
                            content.push(json!({ "type": "document", "source": { "type": "base64", "media_type": "application/pdf", "data": base64 } }));
                            content.push(json!({ "type": "text", "text": file_label(name) }));
                        }
                        Part::Image { name, mime, base64 } => {
                            content.push(json!({ "type": "image", "source": { "type": "base64", "media_type": mime, "data": base64 } }));
                            content.push(json!({ "type": "text", "text": file_label(name) }));
                        }
                    }
                }
                json!({ "role": if m.role == Role::User { "user" } else { "assistant" }, "content": content })
            })
            .collect();
        json!({
            "model": request.model,
            "max_tokens": request.max_tokens,
            "system": request.system,
            "tools": catalog::web_search_tools("anthropic", &request.model),
            "fallbacks": "default",
            "stream": true,
            "messages": messages,
        })
    }
}

impl ModelProvider for Anthropic {
    fn id(&self) -> &str {
        "anthropic"
    }

    fn display_name(&self) -> &str {
        &self.endpoint.name
    }

    fn placement(&self) -> Placement {
        Placement::Cloud
    }

    fn list_models(&self) -> BoxFuture<'_, Result<Vec<ModelInfo>, AiError>> {
        Box::pin(async move {
            let client = client(&self.endpoint, Some(Duration::from_secs(10)));
            let url = format!("{}/v1/models?limit=100", self.endpoint.base_url.trim_end_matches('/'));
            let response = self.headers(client.get(url)).send().await.map_err(|e| errors::from_transport(&e))?;
            if !response.status().is_success() {
                return Err(errors::from_response(response).await);
            }
            let body: Value = response.json().await.map_err(|_| AiError::new(ErrorKind::Server))?;
            Ok(body["data"]
                .as_array()
                .into_iter()
                .flatten()
                .filter_map(|m| {
                    let id = m["id"].as_str()?;
                    Some(ModelInfo {
                        id: id.to_string(),
                        display_name: m["display_name"].as_str().unwrap_or(id).to_string(),
                        context_tokens: None,
                        capabilities: catalog::cloud_capabilities(),
                    })
                })
                .collect())
        })
    }

    fn stream<'a>(
        &'a self,
        request: &'a ChatRequest,
        sink: &'a mut (dyn FnMut(ChatChunk) + Send),
    ) -> BoxFuture<'a, Result<Aggregate, AiError>> {
        Box::pin(async move {
            let client = client(&self.endpoint, None);
            let url = format!("{}/v1/messages", self.endpoint.base_url.trim_end_matches('/'));
            let req = self
                .headers(client.post(url))
                .header("anthropic-beta", FALLBACK_BETA)
                .json(&Self::body(request));
            let t = self.endpoint.timeouts;
            sse::stream_request(req, Format::Anthropic, t.first_token, t.idle, sink).await
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ai::provider::{Finish, Message, Timeouts, ChatChunk, ChatRequest, Endpoint, Placement, Role, Part, ErrorKind};
    use crate::ai::testkit::{self, FakeServer};
    use crate::ai::catalog;
    use serde_json::json;

    fn endpoint(base: &str) -> Endpoint {
        Endpoint {
            provider: "anthropic".into(),
            name: "Anthropic".into(),
            base_url: base.into(),
            key: Some("sk-ant-test".into()),
            placement: Placement::Cloud,
            timeouts: Timeouts::for_placement(Placement::Cloud),
        }
    }

    fn request() -> ChatRequest {
        ChatRequest {
            model: "claude-sonnet-5-5".into(),
            system: "sys".into(),
            messages: vec![Message {
                role: Role::User,
                parts: vec![Part::Pdf { name: "a.pdf".into(), base64: "JVBERi0=".into() }, Part::Text("sum it up".into())],
            }],
            tools: vec![],
            response_format: None,
            max_tokens: 1234,
        }
    }

    #[tokio::test]
    async fn streams_text_and_sources() {
        let fake = FakeServer::start(&[]);
        let p = Anthropic::new(endpoint(&fake.base));
        let mut cites = Vec::new();
        let mut sink = |c: ChatChunk| {
            if let ChatChunk::Citation { url, .. } = c {
                cites.push(url);
            }
        };
        let agg = p.stream(&request(), &mut sink).await.unwrap();
        assert_eq!(agg.text, "Cats sleep a lot.");
        assert_eq!(agg.finish, Some(Finish::Stop));
        assert_eq!(cites, ["https://example.com/cats"]);

        let req = &fake.requests()[0];
        assert_eq!(req["path"], "/v1/messages");
        assert_eq!(req["body"]["stream"], true);
        // The tool is exactly what providers.json says for this model.
        let ws = &testkit::load_json("providers.json")["webSearch"]["anthropic"];
        assert_eq!(req["body"]["tools"][0], json!({ "type": ws["type"], "name": ws["name"], "max_uses": ws["max_uses"] }));
        assert_eq!(req["body"]["messages"][0]["content"][0]["type"], "document");
        assert!(req["origin"].is_null());
    }

    #[tokio::test]
    async fn refusal_and_errors() {
        let fake = FakeServer::start(&["--fail", "refuse"]);
        let agg = Anthropic::new(endpoint(&fake.base)).stream(&request(), &mut |_| {}).await.unwrap();
        assert_eq!((agg.finish, agg.refusal.as_deref()), (Some(Finish::Refusal), Some("")));

        let fake = FakeServer::start(&["--fail", "401"]);
        let err = Anthropic::new(endpoint(&fake.base)).stream(&request(), &mut |_| {}).await.unwrap_err();
        assert_eq!(err.kind, ErrorKind::Auth);

        let fake = FakeServer::start(&["--fail", "overloaded"]);
        let err = Anthropic::new(endpoint(&fake.base)).stream(&request(), &mut |_| {}).await.unwrap_err();
        assert_eq!((err.kind, err.status), (ErrorKind::Overloaded, Some(529)));

        let fake = FakeServer::start(&["--fail", "cut"]);
        let agg = Anthropic::new(endpoint(&fake.base)).stream(&request(), &mut |_| {}).await.unwrap();
        assert_eq!(agg.error, Some(ErrorKind::Interrupted));
    }

    #[test]
    fn older_models_get_the_legacy_search_tool() {
        let ws = &testkit::load_json("providers.json")["webSearch"]["anthropic"];
        let mut req = request();
        req.model = "claude-haiku-4-5-20251001".into();
        assert_eq!(Anthropic::body(&req)["tools"][0]["type"], ws["legacyType"]);
        req.model = "claude-sonnet-5-5".into();
        assert_eq!(Anthropic::body(&req)["tools"][0]["type"], ws["type"]);
    }

    #[tokio::test]
    async fn lists_models_with_a_page_size() {
        // This is also the settings window's key check: a good key gets a list, so ✓.
        let fake = FakeServer::start(&[]);
        let models = Anthropic::new(endpoint(&fake.base)).list_models().await.unwrap();
        assert_eq!(models.iter().map(|m| m.id.as_str()).collect::<Vec<_>>(), ["llama3.2", "nomic-embed-text"]);
        assert!(models.iter().all(|m| m.capabilities == catalog::cloud_capabilities() && m.display_name == m.id));
        let log = fake.requests();
        assert_eq!(log.len(), 1);
        assert_eq!((log[0]["method"].as_str(), log[0]["path"].as_str()), (Some("GET"), Some("/v1/models?limit=100")));
        assert!(log[0]["origin"].is_null());
    }

    #[test]
    fn images_are_image_blocks() {
        let mut req = request();
        req.messages[0].parts = vec![Part::Image { name: "c.png".into(), mime: "image/png".into(), base64: "AA==".into() }];
        let body = Anthropic::body(&req);
        assert_eq!(body["messages"][0]["content"][0]["source"]["media_type"], "image/png");
        assert_eq!(body["messages"][0]["content"][1]["text"], "File: c.png");
        assert_eq!(body["fallbacks"], "default");
    }

    #[test]
    fn a_missing_or_empty_key_sends_no_key_header() {
        for key in [None, Some(String::new())] {
            let provider = Anthropic::new(Endpoint { key, ..endpoint("http://127.0.0.1:1") });
            let req = provider.headers(reqwest::Client::new().get("http://127.0.0.1:1/v1/models")).build().unwrap();
            assert!(req.headers().get("x-api-key").is_none(), "{:?}", req.headers());
        }
    }
}
