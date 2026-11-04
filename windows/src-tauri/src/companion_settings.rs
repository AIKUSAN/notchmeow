// The companion settings (sub-project F3a, docs/COMPANION-CONTRACT.md "Settings", `cleanCompanionSettings`): the Rust twin of shared/companion-core.js's clean-up, which
// keeps the `companion` object of settings.json — `{humor, useMemory, seeSessions, polishRecap, recapDismissals, lastRecapDay, cloudNoticeShown}` — to what the contract
// allows. The cleaner has no state and no I/O; `settings::sanitized` runs the object through it on load and on every save, so a hand-edited or half-written value can
// never fail the settings file or reach the island.

use std::collections::BTreeSet;

use serde_json::{json, Map, Value};

/// The humor IDs, in the contract's order (`HUMOR_LEVELS`).
const HUMOR_LEVELS: [&str; 3] = ["off", "little", "more"];
/// A dismissal count is capped here (`RECAP_MUTE_AT`).
const RECAP_MUTE_AT: u64 = 2;
/// The most cloud notices kept (the contract's 16).
const SHOWN_MAX: usize = 16;
/// The largest whole number a JavaScript number holds exactly (`Number.isSafeInteger`): 2^53 - 1.
const MAX_SAFE: f64 = 9_007_199_254_740_991.0;

/// A stored count: a whole number from 1 up to 2^53 - 1 (a JSON float with no fraction counts, `2.0` as in JavaScript), else None. Never a fraction, a negative, zero, text or 1e300.
fn whole_count(v: Option<&Value>) -> Option<u64> {
    v.and_then(Value::as_f64).filter(|f| f.fract() == 0.0 && *f >= 1.0 && *f <= MAX_SAFE).map(|f| f as u64)
}

/// The days of a month in a year, the Gregorian leap rule (year 0 is a leap year, as in JavaScript's Date).
fn days_in_month(year: u32, month: u32) -> u32 {
    match month {
        4 | 6 | 9 | 11 => 30,
        2 if year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) => 29,
        2 => 28,
        _ => 31,
    }
}

/// True for a real calendar day written `YYYY-MM-DD` in ASCII digits (the contract's `civilDay`): 2026-02-30 is not one, nor is 2025-02-29 or 2026-1-01.
fn is_day(s: &str) -> bool {
    let b = s.as_bytes();
    if b.len() != 10 || b[4] != b'-' || b[7] != b'-' {
        return false;
    }
    let part = |r: std::ops::Range<usize>| -> Option<u32> {
        let d = &b[r];
        if d.iter().all(u8::is_ascii_digit) {
            std::str::from_utf8(d).ok()?.parse().ok()
        } else {
            None
        }
    };
    match (part(0..4), part(5..7), part(8..10)) {
        (Some(y), Some(m), Some(d)) => (1..=12).contains(&m) && (1..=days_in_month(y, m)).contains(&d),
        _ => false,
    }
}

/// An id of a cloud provider: `^[a-zA-Z][a-zA-Z0-9_-]{0,31}$` (ASCII only).
fn provider_id(s: &str) -> bool {
    let b = s.as_bytes();
    (1..=32).contains(&b.len()) && b[0].is_ascii_alphabetic() && b[1..].iter().all(|c| c.is_ascii_alphanumeric() || *c == b'_' || *c == b'-')
}

/// The Companion settings as they are kept: `{humor, useMemory, seeSessions, polishRecap, recapDismissals, lastRecapDay, cloudNoticeShown}`, each the stated value or
/// its default. Cleaning twice is cleaning once. Never panics.
pub fn clean_companion(raw: &Value) -> Value {
    let none = Map::new();
    let r = raw.as_object().unwrap_or(&none);
    let humor = r.get("humor").and_then(Value::as_str).filter(|h| HUMOR_LEVELS.contains(h)).unwrap_or("little");
    let day = r.get("lastRecapDay").and_then(Value::as_str).filter(|s| is_day(s)).unwrap_or("");
    // A set sorts by bytes, which is the UTF-16 order for these ASCII ids; the list keeps the first 16 after the sort.
    let shown: BTreeSet<&str> = match r.get("cloudNoticeShown") {
        Some(Value::Array(a)) => a.iter().filter_map(Value::as_str).filter(|s| provider_id(s)).collect(),
        _ => BTreeSet::new(),
    };
    json!({
        "humor": humor,
        "useMemory": r.get("useMemory") != Some(&Value::Bool(false)),
        "seeSessions": r.get("seeSessions") != Some(&Value::Bool(false)),
        "polishRecap": r.get("polishRecap") == Some(&Value::Bool(true)),
        "recapDismissals": whole_count(r.get("recapDismissals")).map_or(0, |n| n.min(RECAP_MUTE_AT)),
        "lastRecapDay": day,
        "cloudNoticeShown": shown.into_iter().take(SHOWN_MAX).collect::<Vec<_>>(),
    })
}

/// What a fresh install holds: the defaults of `cleanCompanionSettings(null)`.
pub fn default_value() -> Value {
    clean_companion(&Value::Null)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    fn fixture(name: &str) -> Value {
        let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../tests/fixtures/companion").join(name);
        let text = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
        serde_json::from_str(&text).unwrap_or_else(|e| panic!("parse {}: {e}", path.display()))
    }

    #[test]
    fn every_row_of_settings_cases_json() {
        let fx = fixture("settings-cases.json");
        let cases = fx["cases"].as_array().unwrap();
        assert!(cases.len() >= 10, "{} cases", cases.len());
        for c in cases {
            assert_eq!(clean_companion(&c["raw"]), c["expect"], "{}", c["name"]);
        }
    }

    #[test]
    fn cleaning_twice_is_cleaning_once() {
        for raw in [json!(null), json!({"humor": "more", "recapDismissals": 9, "cloudNoticeShown": ["b", "a", "a"]}), json!({"lastRecapDay": "2026-10-17"}), json!([])] {
            let once = clean_companion(&raw);
            assert_eq!(clean_companion(&once), once, "{raw}");
        }
    }

    #[test]
    fn junk_never_panics() {
        for junk in [json!(5), json!("x"), json!([1]), json!(null), json!({"humor": {}, "cloudNoticeShown": "anthropic"}), json!({"recapDismissals": [], "lastRecapDay": 2026})] {
            assert_eq!(clean_companion(&junk), default_value(), "{junk}");
        }
    }

    #[test]
    fn a_count_is_a_safe_whole_number_the_way_javascript_reads_it() {
        assert_eq!(clean_companion(&json!({"recapDismissals": 2.0}))["recapDismissals"], 2);
        assert_eq!(clean_companion(&json!({"recapDismissals": 9007199254740991u64}))["recapDismissals"], 2, "2^53 - 1 is safe, then capped");
        assert_eq!(clean_companion(&json!({"recapDismissals": 9007199254740993u64}))["recapDismissals"], 0, "past 2^53 - 1 is not safe");
        assert_eq!(clean_companion(&json!({"recapDismissals": 9007199254740992.0}))["recapDismissals"], 0);
        assert_eq!(clean_companion(&json!({"recapDismissals": -1}))["recapDismissals"], 0);
        assert_eq!(clean_companion(&json!({"recapDismissals": 0.0}))["recapDismissals"], 0);
    }

    #[test]
    fn a_day_is_a_real_calendar_day_with_leap_years_and_ascii_digits_only() {
        for (day, kept) in [("2024-02-29", true), ("2000-02-29", true), ("2025-02-29", false), ("1900-02-29", false), ("2026-13-01", false), ("2026-00-10", false), ("2026-04-31", false), ("2026-1-01", false), ("\u{0662}026-01-01", false), ("2026-01-01\n", false)] {
            let got = clean_companion(&json!({"lastRecapDay": day}))["lastRecapDay"].clone();
            assert_eq!(got, if kept { json!(day) } else { json!("") }, "{day:?}");
        }
    }

    #[test]
    fn nothing_stored_is_the_defaults() {
        let d = default_value();
        assert_eq!(d, json!({"humor": "little", "useMemory": true, "seeSessions": true, "polishRecap": false, "recapDismissals": 0, "lastRecapDay": "", "cloudNoticeShown": []}));
    }
}
