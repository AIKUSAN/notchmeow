// OpenAI through the Responses API (`POST /v1/responses`, streaming): hosted web
// search with clickable `url_citation` sources, PDFs as `input_file`, images as
// `input_image`. Every request sends `store: false` and the whole conversation,
// never `previous_response_id`, so OpenAI keeps no conversation state (spec §5).

use std::time::Duration;

use serde_json::{json, Value};

use crate::ai::catalog;
use crate::ai::errors;
use crate::ai::provider::{
    file_label, file_text, http_client as client, AiError, Aggregate, BoxFuture, ChatChunk, ChatRequest, Endpoint,
    ErrorKind, ModelInfo, ModelProvider, Part, Placement, Role,
};
use crate::ai::sse::{self, Format};

pub struct OpenAI {
    pub endpoint: Endpoint,
}

impl OpenAI {
    pub fn new(endpoint: Endpoint) -> Self {
        OpenAI { endpoint }
    }

    fn authed(&self, req: reqwest::RequestBuilder) -> reqwest::RequestBuilder {
        match self.endpoint.key.as_deref().filter(|k| !k.is_empty()) {
            Some(k) => req.bearer_auth(k),
            None => req,
        }
    }

    pub fn body(request: &ChatRequest) -> Value {
        let input: Vec<Value> = request
            .messages
            .iter()
            .map(|m| {
                if m.role == Role::Assistant {
                    return json!({ "role": "assistant", "content": m.plain_text() });
                }
                let mut content = Vec::new();
                for p in &m.parts {
                    match p {
                        Part::Text(t) => content.push(json!({ "type": "input_text", "text": t })),
                        Part::FileText { name, text } => {
                            content.push(json!({ "type": "input_text", "text": file_text(name, text) }))
                        }
                        Part::Pdf { name, base64 } => content.push(json!({
                            "type": "input_file",
                            "filename": name,
                            "file_data": format!("data:application/pdf;base64,{base64}"),
                        })),
                        Part::Image { name, mime, base64 } => {
                            content.push(json!({ "type": "input_text", "text": file_label(name) }));
                            content.push(json!({ "type": "input_image", "image_url": format!("data:{mime};base64,{base64}") }));
                        }
                    }
                }
                json!({ "role": "user", "content": content })
            })
            .collect();
        json!({
            "model": request.model,
            "instructions": request.system,
            "input": input,
            "tools": catalog::web_search_tools("openai", &request.model),
            "stream": true,
            "store": false,
            "max_output_tokens": request.max_tokens,
        })
    }
}

impl ModelProvider for OpenAI {
    fn id(&self) -> &str {
        "openai"
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
            let url = format!("{}/v1/models", self.endpoint.base_url.trim_end_matches('/'));
            let response = self.authed(client.get(url)).send().await.map_err(|e| errors::from_transport(&e))?;
            if !response.status().is_success() {
                return Err(errors::from_response(response).await);
            }
            let body: Value = response.json().await.map_err(|_| AiError::new(ErrorKind::Server))?;
            let models = body["data"]
                .as_array()
                .into_iter()
                .flatten()
                .filter_map(|m| m["id"].as_str())
                .map(|id| ModelInfo { capabilities: catalog::cloud_capabilities(), ..ModelInfo::named(id) })
                .collect();
            Ok(catalog::filter_models("openai", models))
        })
    }

    fn stream<'a>(
        &'a self,
        request: &'a ChatRequest,
        sink: &'a mut (dyn FnMut(ChatChunk) + Send),
    ) -> BoxFuture<'a, Result<Aggregate, AiError>> {
        Box::pin(async move {
            let client = client(&self.endpoint, None);
            let url = format!("{}/v1/responses", self.endpoint.base_url.trim_end_matches('/'));
            let req = self.authed(client.post(url)).json(&Self::body(request));
            let t = self.endpoint.timeouts;
            sse::stream_request(req, Format::OpenAIResponses, t.first_token, t.idle, sink).await
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ai::provider::{Finish, Message, Timeouts, ChatChunk, ChatRequest, Endpoint, Placement, Role, Part, ErrorKind};
    use crate::ai::testkit::{self, FakeServer};
    use serde_json::json;
    use std::time::Duration;

    fn endpoint(base: &str) -> Endpoint {
        Endpoint {
            provider: "openai".into(),
            name: "OpenAI".into(),
            base_url: base.into(),
            key: Some("sk-test".into()),
            placement: Placement::Cloud,
            timeouts: Timeouts::for_placement(Placement::Cloud),
        }
    }

    fn request() -> ChatRequest {
        ChatRequest {
            model: "gpt-6.1-sol".into(),
            system: "sys".into(),
            messages: vec![
                Message { role: Role::User, parts: vec![Part::Text("first".into())] },
                Message { role: Role::Assistant, parts: vec![Part::Text("answer".into())] },
                Message {
                    role: Role::User,
                    parts: vec![
                        Part::Pdf { name: "a.pdf".into(), base64: "JVBERi0=".into() },
                        Part::Image { name: "c.png".into(), mime: "image/png".into(), base64: "AA==".into() },
                        Part::Text("and these?".into()),
                    ],
                },
            ],
            tools: vec![],
            response_format: None,
            max_tokens: 1234,
        }
    }

    #[tokio::test]
    async fn every_request_sends_store_false_and_the_whole_history() {
        let fake = FakeServer::start(&[]);
        let p = OpenAI::new(endpoint(&fake.base));
        let mut cites = Vec::new();
        let agg = p
            .stream(&request(), &mut |c| {
                if let ChatChunk::Citation { url, title } = c {
                    cites.push((url, title));
                }
            })
            .await
            .unwrap();
        assert_eq!(agg.text, "Cats sleep a lot.");
        assert_eq!(agg.finish, Some(Finish::Stop));
        assert_eq!(cites, [("https://example.com/cats".to_string(), "Cat sleep facts".to_string())]);

        let log = fake.requests();
        let body = &log.iter().find(|r| r["path"] == "/v1/responses").unwrap()["body"];
        assert_eq!(body["store"], false);
        assert!(body.get("previous_response_id").is_none());
        // The tool is exactly what providers.json says.
        assert_eq!(body["tools"][0], testkit::load_json("providers.json")["webSearch"]["openai"]);
        assert_eq!(body["input"].as_array().unwrap().len(), 3);
        assert_eq!(body["input"][1], json!({ "role": "assistant", "content": "answer" }));
        let last = &body["input"][2]["content"];
        assert_eq!(last[0]["type"], "input_file");
        assert_eq!(last[0]["file_data"], "data:application/pdf;base64,JVBERi0=");
        assert_eq!(last[2]["image_url"], "data:image/png;base64,AA==");
    }

    #[tokio::test]
    async fn refusal_billing_and_overload() {
        let fake = FakeServer::start(&["--fail", "refuse"]);
        let agg = OpenAI::new(endpoint(&fake.base)).stream(&request(), &mut |_| {}).await.unwrap();
        assert_eq!(agg.refusal.as_deref(), Some("I can't help with that."));

        let fake = FakeServer::start(&["--fail", "billing"]);
        let err = OpenAI::new(endpoint(&fake.base)).stream(&request(), &mut |_| {}).await.unwrap_err();
        assert_eq!((err.kind, err.code.as_deref()), (ErrorKind::Billing, Some("insufficient_quota")));

        let fake = FakeServer::start(&["--fail", "overloaded"]);
        let err = OpenAI::new(endpoint(&fake.base)).stream(&request(), &mut |_| {}).await.unwrap_err();
        assert_eq!((err.kind, err.retry_after), (ErrorKind::Overloaded, Some(7)));
    }

    /// A reasoning model streams an event about every 100 s for five minutes: each one resets
    /// the 120 s silence clock, so the turn completes. Simulated clock, no real wait.
    #[tokio::test(start_paused = true)]
    async fn reasoning_events_keep_a_cloud_turn_alive_past_the_silence_limit() {
        let secs = Duration::from_secs;
        let mut script = vec![(secs(1), json!({ "type": "response.in_progress" }).to_string())];
        for kind in ["response.reasoning_summary_part.added", "response.reasoning_summary_text.delta", "response.in_progress"] {
            script.push((secs(100), json!({ "type": kind, "delta": "thinking" }).to_string()));
        }
        script.push((secs(100), json!({ "type": "response.output_text.delta", "delta": "Done thinking." }).to_string()));
        script.push((secs(0), json!({ "type": "response.completed" }).to_string()));
        let base = testkit::paced_sse_server(script).await;
        let agg = OpenAI::new(endpoint(&base)).stream(&request(), &mut |_| {}).await.expect("not cut off");
        assert_eq!((agg.text.as_str(), agg.error, agg.finish), ("Done thinking.", None, Some(Finish::Stop)));
    }

    #[tokio::test(start_paused = true)]
    async fn real_silence_of_120_seconds_still_ends_the_turn() {
        // The control: after the first event, 121 s with nothing is a cut stream.
        let secs = Duration::from_secs;
        let script = vec![
            (secs(1), json!({ "type": "response.in_progress" }).to_string()),
            (secs(121), json!({ "type": "response.completed" }).to_string()),
        ];
        let base = testkit::paced_sse_server(script).await;
        let agg = OpenAI::new(endpoint(&base)).stream(&request(), &mut |_| {}).await.unwrap();
        assert_eq!(agg.error, Some(ErrorKind::Interrupted));
    }

    /// A request never carries an empty bearer token: no key, no Authorization header.
    #[test]
    fn a_missing_or_empty_key_sends_no_authorization_header() {
        for key in [None, Some(String::new())] {
            let provider = OpenAI::new(Endpoint { key, ..endpoint("http://127.0.0.1:1") });
            let req = provider.authed(reqwest::Client::new().get("http://127.0.0.1:1/v1/models")).build().unwrap();
            assert!(req.headers().get("authorization").is_none(), "{:?}", req.headers());
        }
        let keyed = OpenAI::new(endpoint("http://127.0.0.1:1"));
        let req = keyed.authed(reqwest::Client::new().get("http://127.0.0.1:1/v1/models")).build().unwrap();
        assert_eq!(req.headers()["authorization"], "Bearer sk-test");
    }
}
