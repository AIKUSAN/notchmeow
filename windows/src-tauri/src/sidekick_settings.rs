// The Sidekick settings (sub-project F1, docs/SIDEKICK-CONTRACT.md, `cleanSidekickSettings`): the Rust twin of shared/sidekick-core.js's clean-up, which keeps the
// `sidekick` object of settings.json — `{on, local, dismissals}` — to what the contract allows. The cleaner has no state and no I/O; `settings::sanitized` runs the
// object through it on load and on every save, so a hand-edited or half-written value can never fail the file or reach the island, and the object is never dropped
// by a save that only knew about other settings.

use serde_json::{json, Map, Value};

/// The five kinds a note can be: frozen contract values, in this order. A stored count for any other word is dropped.
pub const KINDS: [&str; 5] = ["recap", "stuck.loop", "stuck.errors", "stuck.waiting", "stuck.silent"];
/// A kind dismissed this many times is muted.
pub const MUTE_AT: u64 = 2;

/// A stored count: a whole number from 1 up stays (at most `MUTE_AT`), anything else (text, a fraction, a negative, null, a boolean) is 0. `2.0` is a whole number, as it
/// is in JavaScript.
fn count(v: Option<&Value>) -> u64 {
    v.and_then(Value::as_f64)
        .filter(|f| f.is_finite() && f.fract() == 0.0 && *f > 0.0)
        .map(|f| f.min(MUTE_AT as f64) as u64)
        .unwrap_or(0)
}

/// The dismissals as they are kept: every kind once, in order, each a count from 0 to 2. Unknown kinds go. Never panics.
pub fn clean_dismissals(raw: &Value) -> Value {
    let none = Map::new();
    let r = raw.as_object().unwrap_or(&none);
    let mut out = Map::new();
    for kind in KINDS {
        out.insert(kind.to_string(), json!(count(r.get(kind))));
    }
    Value::Object(out)
}

/// Everything the Sidekick saves, cleaned: `{ on, local, dismissals }`. `on` and `local` are on unless they are the boolean `false`; anything else (the text "false", 0,
/// null) is on. Cleaning twice is cleaning once. Never panics.
pub fn clean_sidekick(raw: &Value) -> Value {
    let none = Map::new();
    let r = raw.as_object().unwrap_or(&none);
    json!({
        "on": r.get("on") != Some(&Value::Bool(false)),
        "local": r.get("local") != Some(&Value::Bool(false)),
        "dismissals": clean_dismissals(r.get("dismissals").unwrap_or(&Value::Null)),
    })
}

/// What a fresh install holds: everything on, nothing dismissed.
pub fn default_value() -> Value {
    clean_sidekick(&Value::Null)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    fn fixture(name: &str) -> Value {
        let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../tests/fixtures/sidekick").join(name);
        let text = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
        serde_json::from_str(&text).unwrap_or_else(|e| panic!("parse {}: {e}", path.display()))
    }

    #[test]
    fn the_clean_up_replays_the_fixture() {
        let fx = fixture("settings-cases.json");
        let kinds: Vec<&str> = fx["kinds"].as_array().unwrap().iter().map(|k| k.as_str().unwrap()).collect();
        assert_eq!(kinds, KINDS, "the five kinds are the contract's, in its order");
        let cases = fx["cases"].as_array().unwrap();
        assert!(cases.len() >= 15, "{} cases", cases.len());
        for c in cases {
            assert_eq!(clean_sidekick(&c["raw"]), c["clean"], "{}", c["name"]);
        }
    }

    #[test]
    fn nothing_stored_is_everything_on_and_nothing_dismissed() {
        let d = default_value();
        assert_eq!(d["on"], true);
        assert_eq!(d["local"], true);
        for k in KINDS {
            assert_eq!(d["dismissals"][k], 0, "{k}");
        }
        assert_eq!(d["dismissals"].as_object().unwrap().len(), 5);
    }

    #[test]
    fn bad_values_are_cleaned_and_unknown_words_are_dropped() {
        let raw = json!({"on": "false", "local": 0, "dismissals": {"recap": 7, "stuck.loop": -3, "stuck.errors": 1.5, "stuck.waiting": "2", "stuck.silent": 2.0, "bogus": 2}, "extra": 1});
        let c = clean_sidekick(&raw);
        assert_eq!(c["on"], true, "the text false is not the boolean");
        assert_eq!(c["local"], true, "zero is not the boolean");
        assert_eq!(c["dismissals"], json!({"recap": 2, "stuck.loop": 0, "stuck.errors": 0, "stuck.waiting": 0, "stuck.silent": 2}));
        assert!(c.get("extra").is_none() && c["dismissals"].get("bogus").is_none());
        for odd in [json!(null), json!(7), json!("x"), json!([1]), json!({"dismissals": [1]}), json!({"dismissals": "recap"})] {
            let c = clean_sidekick(&odd);
            assert_eq!((c["on"].clone(), c["dismissals"]["recap"].clone()), (json!(true), json!(0)), "{odd}");
        }
        assert_eq!(clean_sidekick(&json!({"on": false, "local": false}))["on"], false);
        assert_eq!(clean_sidekick(&json!({"on": false, "local": false}))["local"], false);
    }

    #[test]
    fn cleaning_twice_is_cleaning_once() {
        for raw in [json!(null), json!({"on": false, "dismissals": {"recap": 9, "stuck.loop": 1}}), json!({"dismissals": {"x": 1}}), json!([])] {
            let once = clean_sidekick(&raw);
            assert_eq!(clean_sidekick(&once), once, "{raw}");
        }
    }

    #[test]
    fn a_huge_or_odd_number_is_a_count_the_way_javascript_reads_it() {
        let c = clean_sidekick(&json!({"dismissals": {"recap": 1e300, "stuck.loop": 18446744073709551615u64, "stuck.errors": 0.0, "stuck.waiting": -0.0, "stuck.silent": 1.0000000000000002}}));
        assert_eq!(c["dismissals"], json!({"recap": 2, "stuck.loop": 2, "stuck.errors": 0, "stuck.waiting": 0, "stuck.silent": 0}));
    }
}
