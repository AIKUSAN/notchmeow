// Which model answers. A pure function of the inputs, identical to `route()` in
// tests/fixtures/ai/reference.py; `router_cases` runs every case in
// router-cases.json.

use serde::{Deserialize, Serialize};

use crate::ai::catalog;
use crate::ai::provider::{ErrorKind, Placement};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ModelRef {
    pub provider: String,
    /// Empty when a pre-E1 file picked a provider without a model; `settings::migrate` fills it.
    #[serde(default)]
    pub model: String,
}

/// The JSON word `"auto"`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AutoWord {
    Auto,
}

/// A per-feature setting: `"auto"` or `{"provider": …, "model": …}`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(untagged)]
pub enum Choice {
    Explicit(ModelRef),
    Auto(AutoWord),
}

impl Default for Choice {
    fn default() -> Self {
        Choice::Auto(AutoWord::Auto)
    }
}

impl Choice {
    pub fn is_auto(&self) -> bool {
        matches!(self, Choice::Auto(_))
    }
}

/// A local or network model that answered discovery, in discovery order.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Ready {
    pub provider: String,
    pub model: String,
    pub placement: Placement,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RouteInput {
    pub setting: Choice,
    pub preferred_cloud: String,
    /// Cloud providers with a key.
    pub keys: Vec<String>,
    pub online: bool,
    pub local_ready: Vec<Ready>,
    pub last_used_local: Option<ModelRef>,
    pub apple_ready: bool,
    pub failure: Option<ErrorKind>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Outcome {
    Ok,
    Fallback,
    Error,
    RetryCountdown,
    EmptyState,
    Interrupted,
    Cancelled,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RouteResult {
    pub primary: Option<String>,
    pub outcome: Outcome,
    pub answered_by: Option<String>,
    pub label: Option<Placement>,
    pub error_kind: Option<ErrorKind>,
}

/// The Preferred cloud, then the others of Claude plan / Claude API / OpenAI, then Google — the first that is ready.
/// `keys` holds the cloud providers with a key, plus `claudeCode` when the user connected it and the last check found
/// Claude Code signed in.
pub fn cloud_choice(input: &RouteInput) -> Option<String> {
    let preferred = input.preferred_cloud.as_str();
    let mut order = vec![preferred];
    order.extend(["claudeCode", "anthropic", "openai"].into_iter().filter(|p| *p != preferred));
    order.push("google");
    order.into_iter().find(|p| input.keys.iter().any(|k| k == p)).map(str::to_string)
}

/// The last-used local model if it is still ready, else the first ready one, else Apple.
pub fn local_choice(input: &RouteInput) -> Option<Ready> {
    if let Some(last) = &input.last_used_local {
        if let Some(r) = input
            .local_ready
            .iter()
            .find(|r| r.provider == last.provider && r.model == last.model)
        {
            return Some(r.clone());
        }
    }
    if let Some(first) = input.local_ready.first() {
        return Some(first.clone());
    }
    if input.apple_ready {
        return Some(Ready { provider: "apple".into(), model: "system".into(), placement: Placement::Local });
    }
    None
}

fn placement(input: &RouteInput, provider: &str) -> Placement {
    if catalog::is_cloud(provider) {
        return Placement::Cloud;
    }
    if provider == "apple" {
        return Placement::Local;
    }
    input
        .local_ready
        .iter()
        .find(|r| r.provider == provider)
        .map(|r| r.placement)
        .unwrap_or(Placement::Local)
}

fn result(primary: &str, outcome: Outcome, answered_by: Option<&str>, label: Option<Placement>, kind: Option<ErrorKind>) -> RouteResult {
    RouteResult {
        primary: Some(primary.to_string()),
        outcome,
        answered_by: answered_by.map(str::to_string),
        label,
        error_kind: kind,
    }
}

pub fn route(input: &RouteInput) -> RouteResult {
    let auto = input.setting.is_auto();
    let (primary, local) = match &input.setting {
        Choice::Auto(_) => {
            let cloud = cloud_choice(input);
            let local = local_choice(input);
            match (cloud, &local) {
                (Some(c), _) if input.online || local.is_none() => (c, local),
                (_, Some(l)) => (l.provider.clone(), local.clone()),
                _ => {
                    return RouteResult {
                        primary: None,
                        outcome: Outcome::EmptyState,
                        answered_by: None,
                        label: None,
                        error_kind: None,
                    }
                }
            }
        }
        Choice::Explicit(m) => (m.provider.clone(), None),
    };

    let Some(failure) = input.failure else {
        return result(&primary, Outcome::Ok, Some(&primary), Some(placement(input, &primary)), None);
    };
    match failure {
        ErrorKind::Cancelled => result(&primary, Outcome::Cancelled, None, None, None),
        ErrorKind::Interrupted => result(
            &primary,
            Outcome::Interrupted,
            Some(&primary),
            Some(placement(input, &primary)),
            Some(ErrorKind::Interrupted),
        ),
        kind if kind.is_temporary() && auto && catalog::is_cloud(&primary) && local.is_some() => {
            let fallback = local.unwrap();
            result(&primary, Outcome::Fallback, Some(&fallback.provider), Some(fallback.placement), Some(kind))
        }
        kind @ (ErrorKind::RateLimited | ErrorKind::Overloaded) => {
            result(&primary, Outcome::RetryCountdown, None, None, Some(kind))
        }
        kind => result(&primary, Outcome::Error, None, None, Some(kind)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ai::testkit;
    use serde_json::Value;

    #[test]
    fn router_cases() {
        let data = testkit::load_json("router-cases.json");
        let cases = data["cases"].as_array().unwrap();
        assert_eq!(cases.len(), 39, "router-cases.json changed: update this count on purpose");
        for case in cases {
            let mut input = data["defaults"].clone();
            for (k, v) in case["input"].as_object().unwrap() {
                input[k] = v.clone();
            }
            let input: RouteInput = serde_json::from_value(input).unwrap();
            let got = serde_json::to_value(route(&input)).unwrap();
            assert_eq!(got, case["expect"], "case {}", case["name"]);
        }
    }

    #[test]
    fn choice_round_trips_as_the_contract_spells_it() {
        let auto: Choice = serde_json::from_value(Value::String("auto".into())).unwrap();
        assert!(auto.is_auto());
        assert_eq!(serde_json::to_value(&auto).unwrap(), "auto");
        let explicit: Choice = serde_json::from_str(r#"{"provider":"ollama","model":"qwen3.5:2b"}"#).unwrap();
        assert_eq!(explicit, Choice::Explicit(ModelRef { provider: "ollama".into(), model: "qwen3.5:2b".into() }));
        assert!(serde_json::from_value::<Choice>(Value::String("sometimes".into())).is_err());
    }

    #[test]
    fn local_choice_returns_the_model_too() {
        let input = RouteInput {
            setting: Choice::default(),
            preferred_cloud: "anthropic".into(),
            keys: vec![],
            online: true,
            local_ready: vec![
                Ready { provider: "ollama".into(), model: "qwen3.5:2b".into(), placement: Placement::Local },
                Ready { provider: "custom".into(), model: "llama3".into(), placement: Placement::Network },
            ],
            last_used_local: Some(ModelRef { provider: "custom".into(), model: "llama3".into() }),
            apple_ready: false,
            failure: None,
        };
        assert_eq!(local_choice(&input).unwrap().model, "llama3");
    }
}
