// Server-sent events: a byte-level line decoder, and one aggregator per wire
// format (OpenAI chat completions, OpenAI Responses, Anthropic Messages). Each
// aggregator reproduces `agg_*` in tests/fixtures/ai/reference.py exactly;
// `sse_fixtures` folds every recorded stream and compares with its
// `.expected.json`.

use std::collections::BTreeMap;
use std::time::Duration;

use serde_json::Value;

use crate::ai::errors::{self, stream_error_kind};
use crate::ai::provider::{AiError, Aggregate, ChatChunk, Citation, ErrorKind, Finish, ToolCall};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Format {
    OpenAIChat,
    OpenAIResponses,
    Anthropic,
}

#[cfg(test)]
impl Format {
    /// The fixture folder under tests/fixtures/ai/sse/.
    pub fn dir(self) -> &'static str {
        match self {
            Format::OpenAIChat => "openai-chat",
            Format::OpenAIResponses => "openai-responses",
            Format::Anthropic => "anthropic",
        }
    }
}

/// Splits a byte stream into lines and returns each `data:` payload, trimmed.
/// Bytes are buffered until a newline, so a UTF-8 character or a line split across
/// two network chunks is never cut. Comments, `event:` lines and blanks are dropped.
#[derive(Default)]
pub struct SseDecoder {
    buf: Vec<u8>,
}

impl SseDecoder {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn feed(&mut self, bytes: &[u8]) -> Vec<String> {
        self.buf.extend_from_slice(bytes);
        let mut out = Vec::new();
        while let Some(i) = self.buf.iter().position(|b| *b == b'\n') {
            let line: Vec<u8> = self.buf.drain(..=i).collect();
            if let Some(p) = payload(&line[..line.len() - 1]) {
                out.push(p);
            }
        }
        out
    }

    /// The last line, when the stream ended without a newline.
    pub fn finish(&mut self) -> Vec<String> {
        let line = std::mem::take(&mut self.buf);
        payload(&line).into_iter().collect()
    }
}

fn payload(line: &[u8]) -> Option<String> {
    let line = line.strip_suffix(b"\r").unwrap_or(line);
    let rest = line.strip_prefix(b"data:")?;
    Some(String::from_utf8_lossy(rest).trim().to_string())
}

/// Removes complete `<think>…</think>` blocks, like the reference's non-greedy regex.
/// An unclosed `<think>` is left alone.
pub fn strip_think(text: &str) -> String {
    let mut out = text.to_string();
    let mut from = 0;
    while let Some(start) = out[from..].find("<think>").map(|i| i + from) {
        match out[start + 7..].find("</think>") {
            Some(end) => {
                out.replace_range(start..start + 7 + end + 8, "");
                from = start;
            }
            None => break,
        }
    }
    out
}

/// Hides `<think>` blocks from text as it streams, holding back a tag split
/// across two deltas until it is complete.
#[derive(Default)]
pub struct ThinkFilter {
    inside: bool,
    pending: String,
}

impl ThinkFilter {
    pub fn push(&mut self, delta: &str) -> String {
        self.pending.push_str(delta);
        let mut out = String::new();
        loop {
            let tag = if self.inside { "</think>" } else { "<think>" };
            if let Some(i) = self.pending.find(tag) {
                if !self.inside {
                    out.push_str(&self.pending[..i]);
                }
                self.pending.drain(..i + tag.len());
                self.inside = !self.inside;
                continue;
            }
            let keep = partial_tag(&self.pending, tag);
            let cut = self.pending.len() - keep;
            if !self.inside {
                out.push_str(&self.pending[..cut]);
            }
            self.pending.drain(..cut);
            return out;
        }
    }
}

/// How many trailing bytes of `s` could be the start of `tag` (tags are ASCII).
fn partial_tag(s: &str, tag: &str) -> usize {
    (1..tag.len()).rev().find(|n| s.ends_with(&tag[..*n])).unwrap_or(0)
}

#[derive(Default)]
struct Block {
    kind: String,
    id: String,
    name: String,
    args: String,
}

/// Folds one stream. `push` returns what the chat can show right away; `finish`
/// returns the whole result in the fixtures' shape.
pub struct Aggregator {
    format: Format,
    text: String,
    calls: Vec<(String, ToolCall)>,
    citations: Vec<Citation>,
    refusal: Option<String>,
    finish: Option<Finish>,
    error: Option<ErrorKind>,
    terminal: bool,
    blocks: BTreeMap<u64, Block>,
    think: ThinkFilter,
}

impl Aggregator {
    pub fn new(format: Format) -> Self {
        Aggregator {
            format,
            text: String::new(),
            calls: Vec::new(),
            citations: Vec::new(),
            refusal: None,
            finish: None,
            error: None,
            terminal: false,
            blocks: BTreeMap::new(),
            think: ThinkFilter::default(),
        }
    }

    /// True once the stream's terminal event arrived: stop reading.
    pub fn is_terminal(&self) -> bool {
        self.terminal
    }

    pub fn push(&mut self, payload: &str) -> Vec<ChatChunk> {
        if payload == "[DONE]" {
            if self.format == Format::OpenAIChat {
                self.terminal = true;
            }
            return Vec::new();
        }
        let Ok(ev) = serde_json::from_str::<Value>(payload) else { return Vec::new() };
        let (finish, error) = (self.finish, self.error);
        let mut out = match self.format {
            Format::OpenAIChat => self.push_chat(&ev),
            Format::OpenAIResponses => self.push_responses(&ev),
            Format::Anthropic => self.push_anthropic(&ev),
        };
        if let Some(f) = self.finish.filter(|f| Some(*f) != finish) {
            out.push(ChatChunk::Finish(f));
        }
        if let Some(e) = self.error.filter(|e| Some(*e) != error) {
            out.push(ChatChunk::Error(e));
        }
        out
    }

    fn text_delta(&mut self, delta: &str, out: &mut Vec<ChatChunk>) {
        self.text.push_str(delta);
        let visible = if self.format == Format::OpenAIChat { self.think.push(delta) } else { delta.to_string() };
        if !visible.is_empty() {
            out.push(ChatChunk::Text(visible));
        }
    }

    fn cite(&mut self, url: &str, title: &str, out: &mut Vec<ChatChunk>) {
        if self.citations.iter().any(|c| c.url == url) {
            return;
        }
        let c = Citation { url: url.to_string(), title: title.to_string() };
        out.push(ChatChunk::Citation { url: c.url.clone(), title: c.title.clone() });
        self.citations.push(c);
    }

    fn push_chat(&mut self, ev: &Value) -> Vec<ChatChunk> {
        let mut out = Vec::new();
        for ch in ev.get("choices").and_then(Value::as_array).into_iter().flatten() {
            let d = ch.get("delta").cloned().unwrap_or(Value::Null);
            if let Some(content) = d.get("content").and_then(Value::as_str) {
                self.text_delta(content, &mut out);
            }
            for tc in d.get("tool_calls").and_then(Value::as_array).into_iter().flatten() {
                let index = tc.get("index").and_then(Value::as_u64).unwrap_or(0);
                let key = index.to_string();
                let pos = match self.calls.iter().position(|(k, _)| *k == key) {
                    Some(p) => p,
                    None => {
                        self.calls.push((key, ToolCall { id: String::new(), name: String::new(), arguments: String::new() }));
                        self.calls.len() - 1
                    }
                };
                let slot = &mut self.calls[pos].1;
                if let Some(id) = tc.get("id").and_then(Value::as_str).filter(|s| !s.is_empty()) {
                    slot.id = id.to_string();
                }
                let f = tc.get("function").cloned().unwrap_or(Value::Null);
                if let Some(name) = f.get("name").and_then(Value::as_str).filter(|s| !s.is_empty()) {
                    slot.name = name.to_string();
                }
                let args = f.get("arguments").and_then(Value::as_str).unwrap_or("");
                slot.arguments.push_str(args);
                out.push(ChatChunk::ToolCall { index: pos, id: slot.id.clone(), name: slot.name.clone(), arguments: args.to_string() });
            }
            if let Some(reason) = ch.get("finish_reason").and_then(Value::as_str).filter(|s| !s.is_empty()) {
                self.finish = Some(match reason {
                    "content_filter" => Finish::Refusal,
                    "length" => Finish::Length,
                    "tool_calls" => Finish::ToolCalls,
                    _ => Finish::Stop,
                });
            }
        }
        out
    }

    fn push_responses(&mut self, ev: &Value) -> Vec<ChatChunk> {
        let mut out = Vec::new();
        let s = |v: &Value, k: &str| v.get(k).and_then(Value::as_str).unwrap_or("").to_string();
        match ev.get("type").and_then(Value::as_str).unwrap_or("") {
            "response.output_text.delta" => self.text_delta(&s(ev, "delta"), &mut out),
            "response.output_item.added" => {
                let item = ev.get("item").cloned().unwrap_or(Value::Null);
                if item.get("type").and_then(Value::as_str) == Some("function_call") {
                    let call = ToolCall { id: s(&item, "call_id"), name: s(&item, "name"), arguments: s(&item, "arguments") };
                    self.calls.push((s(&item, "id"), call));
                }
            }
            "response.function_call_arguments.delta" => {
                let key = s(ev, "item_id");
                if let Some(pos) = self.calls.iter().position(|(k, _)| *k == key) {
                    let delta = s(ev, "delta");
                    let call = &mut self.calls[pos].1;
                    call.arguments.push_str(&delta);
                    out.push(ChatChunk::ToolCall { index: pos, id: call.id.clone(), name: call.name.clone(), arguments: delta });
                }
            }
            "response.function_call_arguments.done" => {
                let key = s(ev, "item_id");
                if let Some((_, call)) = self.calls.iter_mut().find(|(k, _)| *k == key) {
                    call.arguments = s(ev, "arguments");
                }
            }
            "response.output_text.annotation.added" => {
                let a = ev.get("annotation").cloned().unwrap_or(Value::Null);
                if a.get("type").and_then(Value::as_str) == Some("url_citation") {
                    self.cite(&s(&a, "url"), &s(&a, "title"), &mut out);
                }
            }
            "response.refusal.done" => {
                let r = s(ev, "refusal");
                out.push(ChatChunk::Refusal(r.clone()));
                self.refusal = Some(r);
            }
            "response.completed" => {
                self.terminal = true;
                self.finish = Some(if self.refusal.is_some() {
                    Finish::Refusal
                } else if !self.calls.is_empty() {
                    Finish::ToolCalls
                } else {
                    Finish::Stop
                });
            }
            "response.incomplete" => {
                self.terminal = true;
                let reason = ev.pointer("/response/incomplete_details/reason").and_then(Value::as_str);
                self.finish = Some(if reason == Some("content_filter") { Finish::Refusal } else { Finish::Length });
            }
            "response.failed" => {
                self.terminal = true;
                // `error` may be missing, a string or a list, and `code` may not be a string:
                // any of that is an unknown code, which is `bad_request`.
                let code = ev.pointer("/response/error/code").and_then(Value::as_str).unwrap_or("");
                self.error = Some(stream_error_kind(code));
            }
            "error" => self.error = Some(stream_error_kind(&s(ev, "code"))),
            _ => {}
        }
        out
    }

    fn push_anthropic(&mut self, ev: &Value) -> Vec<ChatChunk> {
        let mut out = Vec::new();
        let s = |v: &Value, k: &str| v.get(k).and_then(Value::as_str).unwrap_or("").to_string();
        let index = ev.get("index").and_then(Value::as_u64).unwrap_or(0);
        match ev.get("type").and_then(Value::as_str).unwrap_or("") {
            "content_block_start" => {
                let b = ev.get("content_block").cloned().unwrap_or(Value::Null);
                self.blocks.insert(index, Block { kind: s(&b, "type"), id: s(&b, "id"), name: s(&b, "name"), args: String::new() });
            }
            "content_block_delta" => {
                let d = ev.get("delta").cloned().unwrap_or(Value::Null);
                match d.get("type").and_then(Value::as_str).unwrap_or("") {
                    "text_delta" => self.text_delta(&s(&d, "text"), &mut out),
                    "input_json_delta" => {
                        if let Some(b) = self.blocks.get_mut(&index) {
                            b.args.push_str(&s(&d, "partial_json"));
                        }
                    }
                    "citations_delta" => {
                        let c = d.get("citation").cloned().unwrap_or(Value::Null);
                        self.cite(&s(&c, "url"), &s(&c, "title"), &mut out);
                    }
                    _ => {}
                }
            }
            "message_delta" => {
                let mapped = match ev.pointer("/delta/stop_reason").and_then(Value::as_str) {
                    Some("end_turn") | Some("stop_sequence") => Some(Finish::Stop),
                    Some("max_tokens") => Some(Finish::Length),
                    Some("tool_use") => Some(Finish::ToolCalls),
                    Some("refusal") => Some(Finish::Refusal),
                    _ => None,
                };
                if mapped.is_some() {
                    self.finish = mapped;
                }
            }
            "message_stop" => self.terminal = true,
            "error" => {
                // The same mapping as the Responses events; a missing or odd `error` is an unknown type.
                let kind = ev.pointer("/error/type").and_then(Value::as_str).unwrap_or("");
                self.error = Some(stream_error_kind(kind));
            }
            _ => {}
        }
        out
    }

    pub fn finish(self) -> Aggregate {
        let mut text = self.text;
        let mut refusal = self.refusal;
        let mut calls = self.calls;
        if self.format == Format::OpenAIChat {
            // Chat-completions calls are keyed by their `index`; the reference sorts by it.
            calls.sort_by_key(|(k, _)| k.parse::<u64>().unwrap_or(0));
        }
        let mut tool_calls: Vec<ToolCall> = calls.into_iter().map(|(_, c)| c).collect();
        match self.format {
            Format::OpenAIChat => {
                text = strip_think(&text);
                if self.finish == Some(Finish::Refusal) {
                    refusal = Some(String::new());
                }
            }
            Format::Anthropic => {
                tool_calls = self
                    .blocks
                    .into_values()
                    .filter(|b| b.kind == "tool_use")
                    .map(|b| ToolCall { id: b.id, name: b.name, arguments: b.args })
                    .collect();
                if self.finish == Some(Finish::Refusal) {
                    refusal = Some(std::mem::take(&mut text));
                }
            }
            Format::OpenAIResponses => {}
        }
        let error = self.error.or((!self.terminal).then_some(ErrorKind::Interrupted));
        Aggregate {
            text,
            tool_calls,
            citations: self.citations,
            refusal,
            finish: if error.is_some() { None } else { self.finish },
            error,
        }
    }
}

/// Folds a whole recorded stream at once.
#[cfg(test)]
pub fn aggregate(format: Format, sse: &str) -> Aggregate {
    let mut dec = SseDecoder::new();
    let mut agg = Aggregator::new(format);
    for p in dec.feed(sse.as_bytes()).into_iter().chain(dec.finish()) {
        agg.push(&p);
    }
    agg.finish()
}

/// Sends a streaming request and pumps its events into `sink`.
/// * Nothing back before `first_token` (headers included) → `Err(timeout)`.
/// * An HTTP error → `Err` classified by `errors::from_response`.
/// * Silence longer than `idle` after the first bytes, or a dropped connection,
///   ends the stream; the aggregator then reports `interrupted`.
pub async fn stream_request(
    request: reqwest::RequestBuilder,
    format: Format,
    first_token: Duration,
    idle: Duration,
    sink: &mut (dyn FnMut(ChatChunk) + Send),
) -> Result<Aggregate, AiError> {
    let deadline = tokio::time::Instant::now() + first_token;
    let mut response = match tokio::time::timeout_at(deadline, request.send()).await {
        Err(_) => return Err(AiError::new(ErrorKind::Timeout)),
        Ok(Err(e)) => return Err(errors::from_transport(&e)),
        Ok(Ok(r)) => r,
    };
    if !response.status().is_success() {
        return Err(errors::from_response(response).await);
    }
    let mut decoder = SseDecoder::new();
    let mut agg = Aggregator::new(format);
    let mut first = true;
    loop {
        let next = if first {
            tokio::time::timeout_at(deadline, response.chunk()).await
        } else {
            tokio::time::timeout(idle, response.chunk()).await
        };
        let bytes = match next {
            Err(_) if first => return Err(AiError::new(ErrorKind::Timeout)),
            Err(_) | Ok(Err(_)) => break,
            Ok(Ok(None)) => {
                for p in decoder.finish() {
                    for c in agg.push(&p) {
                        sink(c);
                    }
                }
                break;
            }
            Ok(Ok(Some(b))) => b,
        };
        first = false;
        for p in decoder.feed(&bytes) {
            for c in agg.push(&p) {
                sink(c);
            }
        }
        if agg.is_terminal() {
            break;
        }
    }
    Ok(agg.finish())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ai::testkit;

    const FORMATS: [Format; 3] = [Format::OpenAIChat, Format::OpenAIResponses, Format::Anthropic];

    fn fixtures(format: Format) -> Vec<(String, String, Aggregate)> {
        let dir = testkit::fixtures_dir().join("sse").join(format.dir());
        let mut out = Vec::new();
        for entry in std::fs::read_dir(&dir).unwrap() {
            let path = entry.unwrap().path();
            if path.extension().and_then(|e| e.to_str()) != Some("txt") {
                continue;
            }
            let expected = path.with_extension("expected.json");
            let want: Aggregate = serde_json::from_str(&std::fs::read_to_string(&expected).unwrap()).unwrap();
            let name = path.file_name().unwrap().to_string_lossy().to_string();
            out.push((name, std::fs::read_to_string(&path).unwrap(), want));
        }
        out.sort_by(|a, b| a.0.cmp(&b.0));
        out
    }

    #[test]
    fn sse_fixtures() {
        let mut seen = Vec::new();
        for format in FORMATS {
            for (name, text, want) in fixtures(format) {
                assert_eq!(aggregate(format, &text), want, "{}/{name}", format.dir());
                seen.push(format!("{}/{name}", format.dir()));
            }
        }
        // Every recorded stream runs; these are the ones the spec requires.
        for required in [
            "openai-chat/text-think.txt", "openai-chat/tool-call.txt", "openai-chat/keepalive-cut.txt",
            "openai-chat/content-filter.txt", "openai-chat/crlf.txt", "openai-chat/unicode-separators.txt",
            "openai-responses/text-citations.txt", "openai-responses/tool-call.txt",
            "openai-responses/refusal.txt", "openai-responses/incomplete.txt",
            "openai-responses/failed.txt", "openai-responses/failed-policy.txt",
            "openai-responses/failed-billing.txt", "openai-responses/failed-unknown.txt",
            "openai-responses/error-event.txt", "openai-responses/cut.txt",
            "anthropic/text-websearch.txt", "anthropic/tool-use.txt", "anthropic/refusal.txt",
            "anthropic/error-overloaded.txt", "anthropic/cut.txt",
        ] {
            assert!(seen.iter().any(|s| s == required), "missing fixture {required}");
        }
        assert_eq!(seen.len(), 21, "the SSE fixtures changed: update this count on purpose");
    }

    #[test]
    fn sse_fixtures_byte_by_byte() {
        // The network can split anywhere, even inside a UTF-8 character.
        for format in FORMATS {
            for (name, text, want) in fixtures(format) {
                let mut dec = SseDecoder::new();
                let mut agg = Aggregator::new(format);
                for b in text.as_bytes() {
                    for p in dec.feed(std::slice::from_ref(b)) {
                        agg.push(&p);
                    }
                }
                for p in dec.finish() {
                    agg.push(&p);
                }
                assert_eq!(agg.finish(), want, "{}/{name} split per byte", format.dir());
            }
        }
    }

    #[test]
    fn visible_text_hides_think_blocks_while_streaming() {
        let text = testkit::sse_fixture("openai-chat", "text-think.txt");
        let mut dec = SseDecoder::new();
        let mut agg = Aggregator::new(Format::OpenAIChat);
        let mut shown = String::new();
        for b in text.as_bytes().chunks(7) {
            for p in dec.feed(b) {
                for c in agg.push(&p) {
                    if let ChatChunk::Text(t) = c {
                        shown.push_str(&t);
                    }
                }
            }
        }
        assert_eq!(shown, "Hello from NotchMeow.");
    }

    #[test]
    fn think_filter_holds_split_tags() {
        let mut f = ThinkFilter::default();
        let mut out = String::new();
        for piece in ["Hi <thi", "nk>secret</th", "ink> there <", "b>"] {
            out.push_str(&f.push(piece));
        }
        assert_eq!(out, "Hi  there <b>");
    }

    #[test]
    fn strip_think_matches_the_reference_regex() {
        assert_eq!(strip_think("a<think>x</think>b<think>y</think>c"), "abc");
        assert_eq!(strip_think("a<think>open"), "a<think>open");
        assert_eq!(strip_think("<think>\nplan it\n</think>Hello"), "Hello");
    }

    #[test]
    fn response_failed_maps_its_code_like_an_error_event() {
        // The shared fixtures cover server_error, invalid_prompt, insufficient_quota and an unknown code;
        // the rest of `errors::stream_error_kind`'s table is checked here, through both events.
        let fold = |event: String| {
            let mut agg = Aggregator::new(Format::OpenAIResponses);
            agg.push(&event);
            agg.finish().error
        };
        let failed = |code: &str| format!(r#"{{"type":"response.failed","response":{{"status":"failed","error":{{"code":"{code}"}}}}}}"#);
        let error = |code: &str| format!(r#"{{"type":"error","code":"{code}","message":"x"}}"#);
        for (code, want) in [
            ("rate_limit_exceeded", ErrorKind::RateLimited),
            ("server_is_overloaded", ErrorKind::Overloaded),
            ("slow_down", ErrorKind::Overloaded),
            ("insufficient_quota", ErrorKind::Billing),
            ("credit_balance_exhausted", ErrorKind::Billing),
            ("project_spend_limit_exceeded", ErrorKind::Billing),
            ("organization_usage_limit_exceeded", ErrorKind::Billing),
            ("server_error", ErrorKind::Server),
            ("vector_store_timeout", ErrorKind::Server),
            ("invalid_prompt", ErrorKind::Refusal),
            ("content_policy_violation", ErrorKind::Refusal),
            ("invalid_api_key", ErrorKind::Auth),
            ("context_length_exceeded", ErrorKind::BadRequest),
            ("something_new", ErrorKind::BadRequest),
        ] {
            assert_eq!(fold(failed(code)), Some(want), "response.failed {code}");
            assert_eq!(fold(error(code)), Some(want), "error {code}");
        }
        // No error object at all is still a failure, never `interrupted`, and never a temporary one.
        assert_eq!(
            fold(r#"{"type":"response.failed","response":{"status":"failed"}}"#.into()),
            Some(ErrorKind::BadRequest)
        );
    }

    #[test]
    fn odd_stream_errors_never_panic_and_never_fall_back() {
        let fold = |format: Format, event: &str| {
            let mut agg = Aggregator::new(format);
            agg.push(event);
            agg.finish().error
        };
        // `error` as a string, null, a list or missing; `code` as null, a number or a list: an unknown code.
        for event in [
            r#"{"type":"response.failed","response":{"status":"failed","error":"boom"}}"#,
            r#"{"type":"response.failed","response":{"status":"failed","error":null}}"#,
            r#"{"type":"response.failed","response":{"status":"failed","error":["boom"]}}"#,
            r#"{"type":"response.failed","response":{"status":"failed","error":{"code":null}}}"#,
            r#"{"type":"response.failed","response":{"status":"failed","error":{"code":["x"]}}}"#,
            r#"{"type":"response.failed","response":"gone"}"#,
            r#"{"type":"response.failed"}"#,
            r#"{"type":"error","code":null}"#,
            r#"{"type":"error","code":42}"#,
            r#"{"type":"error","error":"boom"}"#,
            r#"{"type":"error"}"#,
        ] {
            let got = fold(Format::OpenAIResponses, event);
            assert_eq!(got, Some(ErrorKind::BadRequest), "{event}");
            assert!(!got.unwrap().is_temporary(), "{event} must not fall back");
        }
        for event in [
            r#"{"type":"error","error":"boom"}"#,
            r#"{"type":"error","error":null}"#,
            r#"{"type":"error","error":["overloaded_error"]}"#,
            r#"{"type":"error","error":{"type":null}}"#,
            r#"{"type":"error","error":{"type":7}}"#,
            r#"{"type":"error"}"#,
        ] {
            assert_eq!(fold(Format::Anthropic, event), Some(ErrorKind::BadRequest), "{event}");
        }
    }

    #[test]
    fn lines_end_at_newline_only() {
        // U+2028, U+0085, a vertical tab and a lone CR inside a data line don't split it; CRLF still ends one.
        let mut dec = SseDecoder::new();
        let got = dec.feed("data: {\"a\":\"x\u{2028}y\u{85}z\u{b}w\rv\"}\r\ndata: [DONE]\n".as_bytes());
        assert_eq!(got, vec!["{\"a\":\"x\u{2028}y\u{85}z\u{b}w\rv\"}".to_string(), "[DONE]".to_string()]);
    }

    #[test]
    fn non_json_and_comment_lines_are_skipped() {
        let mut dec = SseDecoder::new();
        let got = dec.feed(b": keep-alive\r\n\r\nevent: ping\ndata: {\"a\":1}\r\ndata: [DONE]\ndata: not json\n");
        assert_eq!(got, vec!["{\"a\":1}".to_string(), "[DONE]".to_string(), "not json".to_string()]);

        // Verify aggregator skips non-JSON: push "not json" produces no chunks
        let mut agg = Aggregator::new(Format::OpenAIChat);
        for payload in got {
            let chunks = agg.push(&payload);
            if payload == "not json" {
                assert_eq!(chunks, Vec::new(), "non-JSON should produce no chunks");
            }
        }

        // Verify aggregate is unchanged (same result without "not json")
        let mut dec2 = SseDecoder::new();
        let got2 = dec2.feed(b": keep-alive\r\n\r\nevent: ping\ndata: {\"a\":1}\r\ndata: [DONE]\n");
        let mut agg2 = Aggregator::new(Format::OpenAIChat);
        for payload in got2 {
            agg2.push(&payload);
        }
        assert_eq!(agg.finish(), agg2.finish(), "aggregate should be unchanged with non-JSON line");
    }
}
