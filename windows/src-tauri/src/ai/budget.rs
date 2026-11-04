// How much of a file a model gets, and how much history fits. `budget` is `budget()` and
// `messages_to_drop` is `trim_history()` from tests/fixtures/ai/reference.py; `budget_cases` and
// `history_cases` run budget-cases.json and history-cases.json. "Characters" are Unicode scalar
// values (`chars()`), never bytes.

use serde::{Deserialize, Serialize};

use crate::ai::catalog;
use crate::ai::provider::{Message, Part, Placement};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Budget {
    pub kept_chars: usize,
    pub kept_lines: usize,
    /// "I read the first 716 lines." when the text was cut; `None` when it all fit.
    pub notice: Option<String>,
}

/// The character budget for one file: `floor(ctx × 7 / 4)`, which is half the context at 3.5
/// characters per token, in integers; unknown local context counts as 4,096 tokens; cloud is
/// capped at 204,800.
pub fn char_budget(placement: Placement, context_tokens: Option<u64>) -> usize {
    let ctx = match (context_tokens, placement) {
        (Some(c), _) => Some(c),
        (None, Placement::Cloud) => None,
        (None, _) => Some(catalog::DEFAULT_LOCAL_CONTEXT_TOKENS),
    };
    // Saturating: a server can report any context, and an overflow must not panic.
    let chars = ctx.map(|c| (c.saturating_mul(catalog::BUDGET_CHARS_NUMERATOR) / catalog::BUDGET_CHARS_DENOMINATOR) as usize);
    match placement {
        Placement::Cloud => chars.map_or(catalog::CLOUD_TEXT_CAP_CHARS, |c| c.min(catalog::CLOUD_TEXT_CAP_CHARS)),
        _ => chars.unwrap_or(0),
    }
}

pub fn budget(placement: Placement, context_tokens: Option<u64>, text: &str) -> Budget {
    let chars = char_budget(placement, context_tokens);
    let total = text.chars().count();
    if total <= chars {
        let lines = text.matches('\n').count() + usize::from(!text.is_empty() && !text.ends_with('\n'));
        return Budget { kept_chars: total, kept_lines: lines, notice: None };
    }
    let (mut kept, mut lines) = (0, 0);
    // `split_inclusive('\n')`, not `lines()`: a line ends at \n only (not at a lone \r, U+2028 or U+0085).
    for line in text.split_inclusive('\n') {
        let len = line.chars().count();
        if kept + len > chars {
            break;
        }
        kept += len;
        lines += 1;
    }
    let notice = match lines {
        0 => return Budget { kept_chars: chars, kept_lines: 0, notice: Some("I read the first part of this file.".into()) },
        1 => "I read the first line.".to_string(),
        n => format!("I read the first {n} lines."),
    };
    Budget { kept_chars: kept, kept_lines: lines, notice: Some(notice) }
}

/// The text a model actually receives, with the notice appended so it knows too.
pub fn cut(text: &str, b: &Budget) -> String {
    let kept: String = text.chars().take(b.kept_chars).collect();
    match &b.notice {
        Some(n) => format!("{kept}\n\n[{n}]"),
        None => kept,
    }
}

/// history-cases.json `rule.reservedOutputDivisor`: a quarter of the context is kept for the reply.
pub const RESERVED_OUTPUT_DIVISOR: u64 = 4;
/// history-cases.json `rule.binaryAttachmentChars`: what an image or PDF sent as such counts for.
pub const BINARY_ATTACHMENT_CHARS: usize = 1_000;

/// A message's size in Unicode scalars, the way the history rule counts it: its text, plus each
/// file's text, plus 1,000 for an image or PDF sent as such. The "File: name" labels and the
/// base64 are not counted.
pub fn message_chars(message: &Message) -> usize {
    message
        .parts
        .iter()
        .map(|part| match part {
            Part::Text(text) | Part::FileText { text, .. } => text.chars().count(),
            Part::Image { .. } | Part::Pdf { .. } => BINARY_ATTACHMENT_CHARS,
        })
        .sum()
}

/// `ceil(scalars ÷ 3.5)`, written as `ceil(2n ÷ 7)` in integers so that no platform rounds differently.
fn estimate_tokens(scalars: usize) -> u64 {
    (scalars as u64 * 2).div_ceil(7)
}

/// How many of the oldest turns to drop so the conversation fits a small model: `trim_history`
/// in tests/fixtures/ai/reference.py, whose cases `history_cases` runs. `lengths` are each turn's
/// `message_chars`, oldest first.
///
/// Cloud is never trimmed. For local and network models the budget is the context (4,096 when
/// unknown) minus a quarter kept for the reply. While the system prompt plus the remaining turns
/// cost more than that and more than one turn remains, the oldest two go (one, when two are left,
/// so the latest never does). The system prompt and the latest turn always stay.
pub fn messages_to_drop(placement: Placement, context_tokens: Option<u64>, system_chars: usize, lengths: &[usize]) -> usize {
    if placement == Placement::Cloud {
        return 0;
    }
    let ctx = context_tokens.unwrap_or(catalog::DEFAULT_LOCAL_CONTEXT_TOKENS);
    let budget = ctx - ctx / RESERVED_OUTPUT_DIVISOR;
    let mut total = system_chars + lengths.iter().sum::<usize>();
    let mut dropped = 0;
    while estimate_tokens(total) > budget && lengths.len() - dropped > 1 {
        let step = (lengths.len() - dropped - 1).min(2);
        total -= lengths[dropped..dropped + step].iter().sum::<usize>();
        dropped += step;
    }
    dropped
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ai::provider::Role;
    use crate::ai::{errors, testkit};
    use serde_json::Value;

    fn placement(s: &str) -> Placement {
        serde_json::from_value(serde_json::Value::String(s.into())).unwrap()
    }

    #[test]
    fn budget_cases() {
        let data = testkit::load_json("budget-cases.json");
        let cases = data["cases"].as_array().unwrap();
        assert_eq!(cases.len(), 13, "budget-cases.json changed: update this count on purpose");
        for case in cases {
            let fill = case.get("fill").and_then(|v| v.as_str()).unwrap_or("a");
            let line_len = case["lineLength"].as_u64().unwrap() as usize;
            let count = case["lineCount"].as_u64().unwrap() as usize;
            let text = format!("{}\n", fill.repeat(line_len - 1)).repeat(count);
            let got = budget(placement(case["placement"].as_str().unwrap()), case["contextTokens"].as_u64(), &text);
            assert_eq!(serde_json::to_value(&got).unwrap(), case["expect"], "case {}", case["name"]);
        }
    }

    #[test]
    fn cut_keeps_scalars_and_tells_the_model() {
        let text = "🐱🐱\n🐱🐱\n";
        let b = Budget { kept_chars: 3, kept_lines: 1, notice: Some("I read the first line.".into()) };
        assert_eq!(cut(text, &b), "🐱🐱\n\n\n[I read the first line.]");
        let all = budget(Placement::Local, None, text);
        assert_eq!(cut(text, &all), text);
    }

    #[test]
    fn the_budget_is_floor_of_ctx_times_seven_quarters() {
        // Integers, so an odd context floors and never rounds: 4,097 × 7 / 4 = 7,169.75.
        assert_eq!(char_budget(Placement::Local, Some(4097)), 7169);
        assert_eq!(char_budget(Placement::Local, Some(4096)), 7168);
        assert_eq!(char_budget(Placement::Local, None), 7168);
        assert_eq!(char_budget(Placement::Network, Some(1)), 1);
        assert_eq!(char_budget(Placement::Cloud, None), 204_800);
        assert_eq!(char_budget(Placement::Cloud, Some(1_000_000)), 204_800);
        // A server can report any context: the product saturates instead of overflowing.
        let _ = char_budget(Placement::Local, Some(u64::MAX));
    }

    #[test]
    fn only_a_newline_ends_a_line() {
        // Each line is 12 scalars with a lone CR, U+2028 and U+0085 inside it. ctx 17 budgets 29: two lines fit, three don't.
        let text = "ab\rcd\u{2028}ef\u{85}gh\n".repeat(3);
        let got = budget(Placement::Local, Some(17), &text);
        assert_eq!(got, Budget { kept_chars: 24, kept_lines: 2, notice: Some("I read the first 2 lines.".into()) });
    }

    /// A `{fill, count}` from history-cases.json: `fill` repeated `count` times.
    fn filled(spec: &Value) -> String {
        spec["fill"].as_str().unwrap().repeat(spec["count"].as_u64().unwrap() as usize)
    }

    /// One turn of a history case as the message the session would send.
    fn message_of(turn: &Value) -> Message {
        let role: Role = serde_json::from_value(turn["role"].clone()).unwrap();
        let mut parts = Vec::new();
        for file in turn.get("files").and_then(Value::as_array).into_iter().flatten() {
            parts.push(match file["kind"].as_str().unwrap() {
                "text" => Part::FileText { name: "notes.txt".into(), text: filled(&file["text"]) },
                "image" => Part::Image { name: "photo.png".into(), mime: "image/png".into(), base64: String::new() },
                "pdf" => Part::Pdf { name: "paper.pdf".into(), base64: String::new() },
                other => panic!("history-cases.json has a new file kind: {other}"),
            });
        }
        parts.push(Part::Text(filled(&turn["text"])));
        Message { role, parts }
    }

    #[test]
    fn history_cases() {
        let data = testkit::load_json("history-cases.json");
        let cases = data["cases"].as_array().unwrap();
        assert_eq!(cases.len(), 12, "history-cases.json changed: update this count on purpose");
        for case in cases {
            let lengths: Vec<usize> =
                case["turns"].as_array().unwrap().iter().map(|t| message_chars(&message_of(t))).collect();
            let system_chars = filled(&case["system"]).chars().count();
            let ctx = case["contextTokens"].as_u64();
            let dropped = messages_to_drop(placement(case["placement"].as_str().unwrap()), ctx, system_chars, &lengths);
            let notice = (dropped > 0).then_some(errors::TOO_LONG);
            let got = serde_json::json!({ "dropped": dropped, "notice": notice });
            assert_eq!(got, case["expect"], "case {}", case["name"]);
        }
    }

    #[test]
    fn history_constants_match_the_fixture() {
        let rule = &testkit::load_json("history-cases.json")["rule"];
        assert_eq!(rule["reservedOutputDivisor"], RESERVED_OUTPUT_DIVISOR);
        assert_eq!(rule["binaryAttachmentChars"], BINARY_ATTACHMENT_CHARS);
        assert_eq!(rule["notice"], errors::TOO_LONG);
    }

    #[test]
    fn a_message_counts_its_text_its_file_text_and_1000_for_an_image_or_pdf() {
        let message = Message {
            role: Role::User,
            parts: vec![
                Part::FileText { name: "notes.txt".into(), text: "abc".into() },
                Part::Image { name: "a.png".into(), mime: "image/png".into(), base64: "x".repeat(50_000) },
                Part::Pdf { name: "b.pdf".into(), base64: "y".repeat(50_000) },
                Part::Text("🐱é".into()),
            ],
        };
        // The "File: notes.txt" labels and the base64 are not counted; 🐱 and é are one scalar each.
        assert_eq!(message_chars(&message), 3 + 1_000 + 1_000 + 2);
    }

    #[test]
    fn the_budget_line_is_the_contracts_down_to_the_scalar() {
        // ctx 5001: budget = 5001 − 1250 = 3751 tokens. That holds 13,128 scalars (ceil(2 × 13,128 ÷ 7) = 3,751)
        // and not 13,129. A float rule ("three quarters of the context, at 3.5 characters per token") would put the line at 13,127.
        assert_eq!(messages_to_drop(Placement::Local, Some(5001), 0, &[6564, 6564]), 0);
        assert_eq!(messages_to_drop(Placement::Local, Some(5001), 0, &[6564, 6565]), 1);
    }

    #[test]
    fn the_latest_turn_an_empty_history_and_cloud_are_never_trimmed() {
        assert_eq!(messages_to_drop(Placement::Local, None, 0, &[20_000]), 0);
        assert_eq!(messages_to_drop(Placement::Local, None, 50_000, &[]), 0);
        assert_eq!(messages_to_drop(Placement::Cloud, Some(1_000), 0, &[999_999, 1]), 0);
    }
}
