// The Sidekick's local voice (sub-project F1, spec "The local voice"): one short question to a model that runs on THIS computer, and its answer as one line of text. The pure part: which model
// may be asked, what the request looks like, and what a reply is cleaned to. The commands (`ai_oneshot`, `ai_local_model`) that call the model are in `ai/mod.rs`.
//
// What makes it safe is what it cannot reach. Only a provider whose placement is `Local` (a server on 127.0.0.1, ::1 or localhost) is ever chosen: a server on another computer
// (`Network`) and every cloud provider are filtered out, whatever the chat's own settings say, and the chat's Auto choice is never consulted. It is one request, not a conversation:
// nothing is stored, the chat's history is untouched, no key is read and nothing is logged.

use crate::ai::provider::{ChatRequest, Message, Part, Placement, Role};
use crate::ai::router::{local_choice, Choice, ModelRef, Ready, RouteInput};

/// The longest request, system text and prompt together, in characters. The facts a note is written from are a few dozen words; Apple's on-device model, which the Mac also asks, takes
/// only a few thousand tokens, so the two apps keep to the same small size.
pub const MAX_REQUEST_CHARS: usize = 1_200;
/// The longest reply that is kept, in characters (the page's own check is stricter: 200).
pub const MAX_REPLY_CHARS: usize = 400;
/// The reply is a sentence: a few dozen tokens.
pub const MAX_REPLY_TOKENS: u32 = 120;
/// How long the model may take (seconds). Then there is no sentence and the template stands.
pub const TIMEOUT_SECS: u64 = 6;

/// Whether a request is small enough to send.
pub fn within_limits(system: &str, prompt: &str) -> bool {
    !prompt.trim().is_empty() && system.chars().count() + prompt.chars().count() <= MAX_REQUEST_CHARS
}

/// The models a one-shot may use: those on this computer only.
pub fn local_only(ready: &[Ready]) -> Vec<Ready> {
    ready.iter().filter(|r| r.placement == Placement::Local).cloned().collect()
}

/// The local model to ask: the last-used local one if it is still ready, else the first ready one (`router::local_choice`, the router's own local rule). Never a network or cloud model,
/// and never the Auto choice: this is the one place a note's words could reach a model, and it must be one on this computer.
pub fn pick(ready: &[Ready], last_used_local: Option<&ModelRef>) -> Option<Ready> {
    let local = local_only(ready);
    let input = RouteInput {
        setting: Choice::default(),
        preferred_cloud: String::new(),
        keys: Vec::new(),
        online: true,
        local_ready: local,
        last_used_local: last_used_local.cloned(),
        apple_ready: false,
        failure: None,
    };
    local_choice(&input).filter(|r| r.placement == Placement::Local)
}

/// The request: one user message, no tools, no history.
pub fn request(model: &str, system: &str, prompt: &str) -> ChatRequest {
    ChatRequest {
        model: model.to_string(),
        system: system.to_string(),
        messages: vec![Message { role: Role::User, parts: vec![Part::Text(prompt.to_string())] }],
        tools: Vec::new(),
        response_format: None,
        max_tokens: MAX_REPLY_TOKENS,
    }
}

/// What a reply is cleaned to: its first line that has words in it, trimmed, without the quotes some models put around a sentence, at most `MAX_REPLY_CHARS`. None when nothing is left.
pub fn clean_reply(text: &str) -> Option<String> {
    let line = text.lines().map(str::trim).find(|l| !l.is_empty())?;
    let line = line.trim_matches(|c: char| matches!(c, '"' | '\'' | '`' | '\u{201C}' | '\u{201D}' | '\u{2018}' | '\u{2019}')).trim();
    if line.is_empty() {
        return None;
    }
    Some(line.chars().take(MAX_REPLY_CHARS).collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ready(provider: &str, model: &str, placement: Placement) -> Ready {
        Ready { provider: provider.into(), model: model.into(), placement }
    }

    #[test]
    fn only_a_model_on_this_computer_is_ever_picked() {
        let all = [
            ready("custom", "llama3", Placement::Network),
            ready("anthropic", "claude", Placement::Cloud),
            ready("ollama", "qwen3.5:2b", Placement::Local),
            ready("lmstudio", "local-model", Placement::Local),
        ];
        let chosen = pick(&all, None).unwrap();
        assert_eq!((chosen.provider.as_str(), chosen.placement), ("ollama", Placement::Local), "the first local one");
        assert!(local_only(&all).iter().all(|r| r.placement == Placement::Local));
        assert_eq!(local_only(&all).len(), 2);
        // Network and cloud only: nothing is picked, however ready they are.
        assert_eq!(pick(&all[..2], None), None);
        assert_eq!(pick(&[], None), None);
        // A server on another computer that was the last used one is not preferred over nothing, nor over a local one.
        let last = ModelRef { provider: "custom".into(), model: "llama3".into() };
        assert_eq!(pick(&all[..2], Some(&last)), None);
        assert_eq!(pick(&all, Some(&last)).unwrap().provider, "ollama");
    }

    #[test]
    fn the_last_used_local_model_comes_first_if_it_is_still_ready() {
        let all = [ready("ollama", "qwen3.5:2b", Placement::Local), ready("lmstudio", "local-model", Placement::Local)];
        let last = ModelRef { provider: "lmstudio".into(), model: "local-model".into() };
        assert_eq!(pick(&all, Some(&last)).unwrap().provider, "lmstudio");
        let gone = ModelRef { provider: "jan".into(), model: "x".into() };
        assert_eq!(pick(&all, Some(&gone)).unwrap().provider, "ollama", "a last-used model that is no longer there is not asked for");
    }

    #[test]
    fn a_request_is_one_short_message_with_no_tools_and_no_history() {
        let r = request("qwen3.5:2b", "Reword this note.", "Note: Claude Code ran 3 steps.");
        assert_eq!(r.model, "qwen3.5:2b");
        assert_eq!(r.messages.len(), 1);
        assert_eq!(r.messages[0].role, Role::User);
        assert_eq!(r.messages[0].plain_text(), "Note: Claude Code ran 3 steps.");
        assert!(r.tools.is_empty() && r.response_format.is_none());
        assert_eq!(r.max_tokens, MAX_REPLY_TOKENS);
        assert_eq!(r.system, "Reword this note.");
    }

    #[test]
    fn a_request_that_is_empty_or_too_big_is_not_sent() {
        assert!(within_limits("system", "a note"));
        assert!(!within_limits("system", ""));
        assert!(!within_limits("system", "   \n"));
        assert!(within_limits(&"s".repeat(200), &"p".repeat(1_000)));
        assert!(!within_limits(&"s".repeat(200), &"p".repeat(1_001)));
        assert!(within_limits("é", &"é".repeat(1_199)), "characters, not bytes");
    }

    #[test]
    fn a_reply_is_one_clean_line() {
        assert_eq!(clean_reply("Claude Code finished 3 steps.").as_deref(), Some("Claude Code finished 3 steps."));
        assert_eq!(clean_reply("\n\n  \"Claude Code finished.\"  \nAnd a second line.").as_deref(), Some("Claude Code finished."));
        assert_eq!(clean_reply("\u{201C}Done.\u{201D}").as_deref(), Some("Done."));
        assert_eq!(clean_reply("`ran`").as_deref(), Some("ran"));
        for none in ["", "   ", "\n\n", "\"\"", "''", "``"] {
            assert_eq!(clean_reply(none), None, "{none:?}");
        }
        let long = "x".repeat(1_000);
        assert_eq!(clean_reply(&long).unwrap().chars().count(), MAX_REPLY_CHARS);
    }
}
