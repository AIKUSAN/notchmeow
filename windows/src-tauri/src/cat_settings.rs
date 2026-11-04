// The Cat section of settings.json (spec §4), cleaned: a port of "Stored settings" in design/prototype/cat-core.js, which decides
// (tests/fixtures/cat/settings-cases.json; docs/CAT-CONTRACT.md "Stored settings"). settings.json is plain text a user can edit and the
// webview hands over whatever it holds, so the block is held as a serde_json::Value, never as a typed struct: one bad field in a typed
// struct would fail the whole settings file. `clean_cat_settings` is the one way in. Raw in, clean out, never a panic. The TypeScript side
// (src/cat/settings.ts) cleans the same way again before it uses a value, and both replay the same fixture.
//
//   { character, motionStyle, collar, furLines, cats: { <catId>: { motion, collar, personality } } }   with all 16 cat IDs once clean.
//
// The same block also holds the Display settings (sub-project B, spec §1), cleaned by `clean_display_settings`, a port of `cleanDisplaySettings` in the same file
// of the contract (tests/fixtures/cat/display-cases.json): { displayMode, pair: [catId, catId], agentCats: { <pillId>: <catId> } }. `clean_cat_settings` still
// returns only the five Cat settings and drops those keys, so the block is cleaned with both, by `clean_cat_block`: a clean-up with the Cat settings alone would
// drop the three display keys at the next save.
//
// And the desktop cat's settings (sub-project H), cleaned by `clean_desktop_settings`, a port of `cleanDesktopSettings` in the same file of the contract
// (tests/fixtures/cat/desktop-cases.json): `desktop: { on, size, spots: { <screenKey>: { x, y } } }`. `clean_cat_block` cleans that too.
//
// And the wardrobe's (sub-project I), cleaned by `clean_wardrobe_settings`, a port of `cleanWardrobeSettings` (tests/fixtures/cat/wardrobe-cases.json): `outfit`, one of the 18 selection IDs.
//
// And the project cats (sub-project P), cleaned by `clean_project_cats`, a port of `cleanProjectCats` in shared/projects-core.js (tests/fixtures/projects/cat-cases.json):
// `projectCats: { <catKey>: <catId> }`, at most 256 in UTF-16 order of the keys. `clean_cat_block` cleans it too.

use serde_json::{json, Map, Value};

/// The cat IDs: frozen contract values, in this order. An unknown stored ID is Shrimpy.
pub const CAT_IDS: [&str; 16] = [
    "shrimpy", "momo", "ginger", "midnight", "latte", "patches", "blue", "snow", "oreo", "mocha", "silver", "cloud", "leo", "button", "puff", "noodle",
];
const MOTION_STYLES: [&str; 2] = ["playful", "classic"];
/// The collar style IDs: frozen, in this order. An unknown stored style is `off`.
const COLLAR_STYLES: [&str; 4] = ["tag", "band", "kerchief", "off"];
/// "No override: use the global setting." Not a motion style and not a collar style.
const FOLLOW: &str = "follow";
const TRAIT_KEYS: [&str; 6] = ["energy", "curiosity", "chatty", "affection", "sass", "mischief"];
/// The six presets and their traits, in TRAIT_KEYS order (personality.ts and personality-cases.json say the same).
const PERSONAS: [(&str, [f64; 6]); 6] = [
    ("balanced", [0.5, 0.5, 0.5, 0.5, 0.5, 0.5]),
    ("chill", [0.12, 0.35, 0.3, 0.65, 0.3, 0.2]),
    ("grumpy", [0.4, 0.3, 0.45, 0.15, 0.95, 0.3]),
    ("sweet", [0.5, 0.55, 0.55, 1.0, 0.1, 0.3]),
    ("hyper", [1.0, 0.9, 0.75, 0.5, 0.3, 1.0]),
    ("chatty", [0.6, 0.7, 1.0, 0.6, 0.35, 0.5]),
];
static NULL: Value = Value::Null;

/// The stored word if it is one of `allowed` (matched exactly: case, spaces and the JSON type all count), else `other`.
fn word(v: Option<&Value>, allowed: &[&'static str], other: &'static str) -> &'static str {
    match v {
        Some(Value::String(s)) => allowed.iter().copied().find(|a| a == s).unwrap_or(other),
        _ => other,
    }
}

/// A trait as stored: a number is held to 0…1; anything else (missing, text, a boolean, null) is 0.5. Minus zero is stored as 0.
fn trait_value(v: Option<&Value>) -> f64 {
    match v.and_then(Value::as_f64) {
        Some(x) if x.is_finite() => (if x < 0.0 { 0.0 } else if x > 1.0 { 1.0 } else { x }) + 0.0,
        _ => 0.5,
    }
}

fn personality(preset: &str, traits: [f64; 6]) -> Value {
    let mut m = Map::new();
    m.insert("preset".into(), json!(preset));
    for (k, v) in TRAIT_KEYS.iter().zip(traits) {
        m.insert((*k).into(), json!(v));
    }
    Value::Object(m)
}

fn balanced() -> Value {
    personality("balanced", PERSONAS[0].1)
}

/// A stored personality to a clean one: an object, or the JSON text of one. Text that is not JSON, and JSON that is not an object, give
/// Balanced. The six traits are held to 0…1 (missing or not a number is 0.5). The preset is kept only when it names one of the six AND the
/// traits are still that preset's (within 1e-9); anything else, a missing or unknown name included, is `custom`.
pub fn clean_personality(raw: &Value) -> Value {
    let parsed;
    let v = match raw {
        Value::String(text) => match serde_json::from_str::<Value>(text) {
            Ok(p) => {
                parsed = p;
                &parsed
            }
            Err(_) => return balanced(),
        },
        other => other,
    };
    let Value::Object(o) = v else { return balanced() };
    let traits: [f64; 6] = std::array::from_fn(|i| trait_value(o.get(TRAIT_KEYS[i])));
    let named = o
        .get("preset")
        .and_then(Value::as_str)
        .and_then(|n| PERSONAS.iter().find(|(name, t)| *name == n && t.iter().zip(&traits).all(|(a, b)| (a - b).abs() <= 1e-9)));
    personality(named.map_or("custom", |p| p.0), traits)
}

/// Everything Settings saves, cleaned. Never panics; unknown keys are dropped; the result always holds all 16 cats.
pub fn clean_cat_settings(raw: &Value) -> Value {
    let none = Map::new();
    let r = raw.as_object().unwrap_or(&none);
    let stored = r.get("cats").and_then(Value::as_object).unwrap_or(&none);
    let mut cats = Map::new();
    for id in CAT_IDS {
        let c = stored.get(id).and_then(Value::as_object).unwrap_or(&none);
        cats.insert(
            id.into(),
            json!({
                "motion": word(c.get("motion"), &MOTION_STYLES, FOLLOW),
                "collar": word(c.get("collar"), &COLLAR_STYLES, FOLLOW),
                "personality": clean_personality(c.get("personality").unwrap_or(&NULL)),
            }),
        );
    }
    json!({
        "character": word(r.get("character"), &CAT_IDS, "shrimpy"),
        "motionStyle": word(r.get("motionStyle"), &MOTION_STYLES, "playful"),
        "collar": word(r.get("collar"), &COLLAR_STYLES, "off"),
        "furLines": r.get("furLines") == Some(&Value::Bool(true)),
        "cats": Value::Object(cats),
    })
}

/// What a fresh install holds in the Cat settings: Shrimpy, Playful, collar off, no fur lines, every cat following the globals with a Balanced personality.
/// (`block_default` is the whole block, with the Display defaults; this is the part `settings-cases.json` pins.)
#[cfg(test)]
pub fn default_value() -> Value {
    clean_cat_settings(&Value::Null)
}

// ── The Display settings (sub-project B) ──────────────────────────────────────────────────────────────────────────────────────────────────

/// The display modes, in the order Settings lists them: frozen contract values. An unknown stored mode is `one`.
pub const DISPLAY_MODES: [&str; 3] = ["one", "perAgent", "two"];
/// Two cats mode's pair before the user picks: Shrimpy and Momo.
const DEFAULT_PAIR: [&str; 2] = ["shrimpy", "momo"];
/// A stored map keeps at most this many pills (the first by code-point order of their IDs), so a hostile file cannot grow it without end.
pub const MAX_AGENT_CATS: usize = 256;

/// A pill ID: a lowercase letter, then lowercase letters, digits, `_` and `-`, 2 to 64 characters, the whole string (`^[a-z][a-z0-9_-]{1,63}$`), and not a prototype name.
pub fn is_pill_id(v: &str) -> bool {
    let b = v.as_bytes();
    (2..=64).contains(&b.len())
        && b[0].is_ascii_lowercase()
        && b[1..].iter().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || *c == b'_' || *c == b'-')
        && v != "constructor"
        && v != "prototype"
}

/// Agent pills are Claude Code's pill (`integration_claude`, despite its prefix) and every `agent_*` pill. Only the fixture check uses it here: the island decides
/// which pill is an agent's.
#[cfg(test)]
pub fn is_agent_pill(v: &str) -> bool {
    is_pill_id(v) && (v == "integration_claude" || (v.starts_with("agent_") && v.len() > 6))
}

/// The default coat of an agent pill (Claude Code Shrimpy, Codex Momo), or None.
pub fn default_agent_cat(id: &str) -> Option<&'static str> {
    if !is_pill_id(id) {
        return None;
    }
    match id {
        "integration_claude" => Some("shrimpy"),
        "agent_codex" => Some("momo"),
        _ => None,
    }
}

/// The cat ID a stored value names, matched exactly; None for anything else.
fn cat_id(v: &Value) -> Option<&'static str> {
    v.as_str().and_then(|s| CAT_IDS.iter().copied().find(|c| *c == s))
}

/// A stored pair to two cat IDs. It may be an array or the JSON text of one (the Mac stores text). Anything that is not two valid cat IDs, whole, is Shrimpy and
/// Momo. Two of the same coat make cat 2 the next coat in CAT_IDS order (after the last one, the first).
pub fn clean_pair(raw: &Value) -> [&'static str; 2] {
    let parsed;
    let v = match raw {
        Value::String(text) => match serde_json::from_str::<Value>(text) {
            Ok(p) => {
                parsed = p;
                &parsed
            }
            Err(_) => return DEFAULT_PAIR,
        },
        other => other,
    };
    let Value::Array(a) = v else { return DEFAULT_PAIR };
    if a.len() != 2 {
        return DEFAULT_PAIR;
    }
    let (Some(x), Some(y)) = (cat_id(&a[0]), cat_id(&a[1])) else { return DEFAULT_PAIR };
    if x == y {
        let at = CAT_IDS.iter().position(|c| *c == y).unwrap_or(0);
        [x, CAT_IDS[(at + 1) % CAT_IDS.len()]]
    } else {
        [x, y]
    }
}

/// A stored map from pill ID to cat ID, cleaned. A pill ID that does not have the shape of one is dropped (`__proto__` and `constructor` included); an unknown pill ID
/// is kept, because agents come and go. A bad coat becomes the pill's default when it has one, and is dropped otherwise (the island gives that agent a coat again).
/// The result has its pills in code-point order, at most MAX_AGENT_CATS of them.
pub fn clean_agent_cats(raw: &Value) -> Value {
    let mut out = Map::new();
    let Some(o) = raw.as_object() else { return Value::Object(out) };
    let mut ids: Vec<&String> = o.keys().filter(|k| is_pill_id(k)).collect();
    ids.sort();
    for id in ids {
        if out.len() >= MAX_AGENT_CATS {
            break;
        }
        if let Some(c) = cat_id(&o[id]) {
            out.insert(id.clone(), json!(c));
        } else if let Some(d) = default_agent_cat(id) {
            out.insert(id.clone(), json!(d));
        }
    }
    Value::Object(out)
}

/// Everything Display saves, cleaned: { displayMode, pair, agentCats }. Never panics.
pub fn clean_display_settings(raw: &Value) -> Value {
    let none = Map::new();
    let r = raw.as_object().unwrap_or(&none);
    json!({
        "displayMode": word(r.get("displayMode"), &DISPLAY_MODES, "one"),
        "pair": clean_pair(r.get("pair").unwrap_or(&NULL)),
        "agentCats": clean_agent_cats(r.get("agentCats").unwrap_or(&NULL)),
    })
}

// ── The desktop cat's settings (sub-project H) ────────────────────────────────────────────────────────────────────────────────────────────────

/// The desktop cat's size IDs: frozen contract values. An unknown stored size is `medium`.
const DESKTOP_SIZES: [&str; 3] = ["small", "medium", "large"];
/// A stored map keeps the spots of at most this many screen arrangements (the first by code-point order of their keys).
pub const MAX_DESKTOP_SPOTS: usize = 32;
/// A spot is two numbers no larger than this in size.
const SPOT_LIMIT: f64 = 100_000.0;

/// One frame of a screen key, `x,y,w,h`: whole numbers of one to seven digits, `x` and `y` with an optional minus sign.
fn frame_of(q: &str) -> Option<[i64; 4]> {
    let parts: Vec<&str> = q.split(',').collect();
    if parts.len() != 4 {
        return None;
    }
    let mut out = [0i64; 4];
    for (i, p) in parts.iter().copied().enumerate() {
        let digits = if i < 2 { p.strip_prefix('-').unwrap_or(p) } else { p };
        if digits.is_empty() || digits.len() > 7 || !digits.bytes().all(|b| b.is_ascii_digit()) {
            return None;
        }
        out[i] = p.parse().ok()?;
    }
    Some(out)
}

/// True for exactly the strings `screenKey` writes (cat-core.js): one to sixteen frames `x,y,w,h` joined with `|`, in sorted order, sizes of at least 1, nothing past a million, and
/// the digits written the way a number is (no leading zero, no `-0`), the whole string.
pub fn is_screen_key(k: &str) -> bool {
    let frames: Vec<&str> = k.split('|').collect();
    if frames.len() > 16 {
        return false;
    }
    let mut rects: Vec<[i64; 4]> = Vec::new();
    for q in frames {
        match frame_of(q) {
            Some(r) => rects.push(r),
            None => return false,
        }
    }
    if rects.iter().any(|r| r.iter().any(|v| v.abs() > 1_000_000) || r[2] < 1 || r[3] < 1) || !rects.windows(2).all(|w| w[0] <= w[1]) {
        return false;
    }
    let written: Vec<String> = rects.iter().map(|r| format!("{},{},{},{}", r[0], r[1], r[2], r[3])).collect();
    written.join("|") == k
}

/// A spot, `{x, y}` of two numbers no larger than 100000 in size, reduced to those two; None for anything else.
fn spot_of(v: &Value) -> Option<Value> {
    let o = v.as_object()?;
    let (x, y) = (o.get("x")?, o.get("y")?);
    let (fx, fy) = (x.as_f64()?, y.as_f64()?);
    (fx.abs() <= SPOT_LIMIT && fy.abs() <= SPOT_LIMIT).then(|| json!({ "x": x, "y": y }))
}

/// A stored map from screen key to spot, cleaned: an object or the JSON text of one (text that is not JSON is `{}`), only the keys `is_screen_key` accepts (`__proto__` is never
/// one), only values that are spots, in code-point order of the keys, the first 32.
pub fn clean_desktop_spots(raw: &Value) -> Value {
    let parsed;
    let v = match raw {
        Value::String(s) => {
            parsed = serde_json::from_str::<Value>(s).unwrap_or(Value::Null);
            &parsed
        }
        other => other,
    };
    let mut out = Map::new();
    let Some(o) = v.as_object() else { return Value::Object(out) };
    let mut keys: Vec<&String> = o.keys().filter(|k| is_screen_key(k)).collect();
    keys.sort();
    for k in keys {
        if out.len() >= MAX_DESKTOP_SPOTS {
            break;
        }
        if let Some(s) = o.get(k.as_str()).and_then(spot_of) {
            out.insert(k.clone(), s);
        }
    }
    Value::Object(out)
}

/// Everything the desktop cat saves, cleaned: `{ on, size, spots }`. `on` is true only for the boolean true (the number 1 and the text "true" are off), `size` one of the three
/// IDs (anything else is `medium`), `spots` as `clean_desktop_spots`. Never panics.
pub fn clean_desktop_settings(raw: &Value) -> Value {
    let none = Map::new();
    let r = raw.as_object().unwrap_or(&none);
    json!({
        "on": r.get("on") == Some(&Value::Bool(true)),
        "size": word(r.get("size"), &DESKTOP_SIZES, "medium"),
        "spots": clean_desktop_spots(r.get("spots").unwrap_or(&NULL)),
    })
}

// ── The wardrobe's settings (sub-project I) ───────────────────────────────────────────────────────────────────────────────────────────────────

/// The 18 outfit selection IDs, in the order of the grid: frozen contract values, because they are stored. Anything else stored is `auto`.
pub const OUTFIT_IDS: [&str; 18] = [
    "auto", "none", "partyhat", "santahat", "witchhat", "bunnyears", "sunglasses", "beanie", "bow", "scarf", "roundglasses", "crown", "bell", "bandana", "fishclip", "flower", "shrimpclip", "blossomclip",
];

/// Everything the wardrobe saves, cleaned: `{ outfit }`. The ID is kept only when it is a string equal to one of the 18, as written (no case folding, no trimming); anything else, or no
/// value, is `auto`. Reads only its own key. Never panics.
pub fn clean_wardrobe_settings(raw: &Value) -> Value {
    json!({ "outfit": word(raw.as_object().and_then(|r| r.get("outfit")), &OUTFIT_IDS, "auto") })
}

// ── The project cats (sub-project P) ──────────────────────────────────────────────────────────────────────────────────────────────────────

/// A stored map keeps the cats of at most this many projects (the first in UTF-16 order of their keys): PROJECT_CATS_MAX in shared/projects-core.js.
pub const PROJECT_CATS_MAX: usize = 256;

/// The invisible and control characters of projects-core.js's INVISIBLE set (bidi overrides, zero-width marks, line separators, the tag block).
fn is_invisible_pj(c: char) -> bool {
    matches!(
        c as u32,
        0x00..=0x1F | 0x7F..=0x9F | 0xAD | 0x61C | 0x180E | 0x200B..=0x200F | 0x202A..=0x202E | 0x2028 | 0x2029 | 0x2060 | 0x2066..=0x2069 | 0xFEFF | 0xFFF9..=0xFFFB | 0xE0000..=0xE007F
    )
}

/// A project's folder name as a key (projects-core.js's isCatKey): not empty, at most 60 code points, no `/` or `\`, no invisible character, and not a prototype name.
fn is_cat_key(k: &str) -> bool {
    !k.is_empty()
        && k.chars().count() <= 60
        && !k.chars().any(|c| c == '/' || c == '\\' || is_invisible_pj(c))
        && !matches!(k, "__proto__" | "constructor" | "prototype")
}

/// The keys in UTF-16 code-unit order, the order the contract sorts in: not the byte order once a key holds a character past U+FFFF.
fn utf16_sorted(mut keys: Vec<&str>) -> Vec<&str> {
    keys.sort_by(|a, b| a.encode_utf16().cmp(b.encode_utf16()));
    keys
}

/// The stored project cats, cleaned: `{ <catKey>: <catId> }`, the keys that are kept (is_cat_key) with a cat ID as value, in UTF-16 order, at most
/// PROJECT_CATS_MAX. Anything that is not a plain object is `{}`. Never panics.
pub fn clean_project_cats(raw: &Value) -> Value {
    let mut out = Map::new();
    let Some(o) = raw.as_object() else { return Value::Object(out) };
    let keys = utf16_sorted(o.keys().map(String::as_str).filter(|k| is_cat_key(k) && cat_id(&o[*k]).is_some()).collect());
    for k in keys.into_iter().take(PROJECT_CATS_MAX) {
        if let Some(c) = cat_id(&o[k]) {
            out.insert(k.to_string(), json!(c));
        }
    }
    Value::Object(out)
}

/// The whole `cat` block: the Cat settings, the Display settings, the desktop cat's, the wardrobe's and the project cats, each cleaned by its own clean-up. This is what `settings::sanitized` runs the block through.
pub fn clean_cat_block(raw: &Value) -> Value {
    let mut block = clean_cat_settings(raw);
    if let (Some(o), Value::Object(display)) = (block.as_object_mut(), clean_display_settings(raw)) {
        for (k, v) in display {
            o.insert(k, v);
        }
    }
    if let Some(o) = block.as_object_mut() {
        o.insert("desktop".to_string(), clean_desktop_settings(raw.get("desktop").unwrap_or(&NULL)));
        o.insert("outfit".to_string(), clean_wardrobe_settings(raw)["outfit"].clone());
        o.insert("projectCats".to_string(), clean_project_cats(raw.get("projectCats").unwrap_or(&NULL)));
    }
    block
}

/// What a fresh install holds in the `cat` block: the Cat defaults and One cat, Shrimpy and Momo, no stored agent coats.
pub fn block_default() -> Value {
    clean_cat_block(&Value::Null)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    fn fixture(name: &str) -> Value {
        let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../tests/fixtures/cat").join(name);
        let text = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
        serde_json::from_str(&text).unwrap_or_else(|e| panic!("parse {}: {e}", path.display()))
    }

    /// Where two values differ: numbers within 1e-9, objects by key (order does not matter), everything else exactly.
    fn differences(a: &Value, b: &Value, at: &str, out: &mut Vec<String>) {
        match (a, b) {
            (Value::Number(x), Value::Number(y)) => {
                if (x.as_f64().unwrap() - y.as_f64().unwrap()).abs() > 1e-9 {
                    out.push(format!("{at}: {x} vs {y}"));
                }
            }
            (Value::Array(x), Value::Array(y)) => {
                if x.len() != y.len() {
                    out.push(format!("{at}: length {} vs {}", x.len(), y.len()));
                }
                for (i, (p, q)) in x.iter().zip(y).enumerate() {
                    differences(p, q, &format!("{at}[{i}]"), out);
                }
            }
            (Value::Object(x), Value::Object(y)) => {
                let (mut kx, mut ky): (Vec<_>, Vec<_>) = (x.keys().collect(), y.keys().collect());
                kx.sort();
                ky.sort();
                if kx != ky {
                    out.push(format!("{at}: keys {kx:?} vs {ky:?}"));
                }
                for (k, p) in x {
                    if let Some(q) = y.get(k) {
                        differences(p, q, &format!("{at}.{k}"), out);
                    }
                }
            }
            _ => {
                if a != b {
                    out.push(format!("{at}: {a} vs {b}"));
                }
            }
        }
    }

    fn assert_same(got: &Value, want: &Value, what: &str) {
        let mut d = Vec::new();
        differences(got, want, "$", &mut d);
        assert!(d.is_empty(), "{what}: {} difference(s), first: {:?}", d.len(), &d[..d.len().min(4)]);
    }

    #[test]
    fn the_ids_words_and_presets_are_the_fixtures() {
        let fx = fixture("settings-cases.json");
        let ids: Vec<&str> = fx["ids"].as_array().unwrap().iter().map(|v| v.as_str().unwrap()).collect();
        assert_eq!(ids, CAT_IDS);
        assert_eq!(fx["follow"], FOLLOW);
        assert_eq!(fx["motionStyles"], json!(MOTION_STYLES));
        assert_eq!(fx["collarStyles"], json!(COLLAR_STYLES));
        let presets = &fixture("personality-cases.json")["presets"];
        for (name, traits) in PERSONAS {
            for (k, v) in TRAIT_KEYS.iter().zip(traits) {
                assert_eq!(presets[name][*k].as_f64(), Some(v), "{name}.{k}");
            }
        }
        assert_eq!(presets.as_object().unwrap().len(), PERSONAS.len());
    }

    #[test]
    fn a_fresh_install_is_the_fixtures_defaults() {
        assert_same(&default_value(), &fixture("settings-cases.json")["defaults"], "defaults");
        let d = default_value();
        assert_eq!((&d["character"], &d["motionStyle"], &d["collar"], &d["furLines"]), (&json!("shrimpy"), &json!("playful"), &json!("off"), &json!(false)));
        let keys: Vec<&str> = d["cats"].as_object().unwrap().keys().map(String::as_str).collect();
        assert_eq!(keys, CAT_IDS);
    }

    #[test]
    fn every_settings_case_of_the_fixture_replays() {
        let cases = fixture("settings-cases.json")["cases"].clone();
        assert!(cases.as_array().unwrap().len() >= 37);
        for c in cases.as_array().unwrap() {
            assert_same(&clean_cat_settings(&c["raw"]), &c["out"], c["name"].as_str().unwrap());
        }
    }

    #[test]
    fn every_personality_case_of_the_fixture_replays() {
        let cases = fixture("settings-cases.json")["personalities"].clone();
        assert!(cases.as_array().unwrap().len() >= 47);
        for c in cases.as_array().unwrap() {
            assert_same(&clean_personality(&c["raw"]), &c["out"], c["name"].as_str().unwrap());
        }
    }

    #[test]
    fn a_number_that_cannot_be_written_in_json_has_no_value_and_a_huge_one_is_held_to_1() {
        // Python's NaN cannot be written in JSON, and serde_json cannot hold NaN or an infinity in a Value at all (the fixture's port note).
        assert!(serde_json::Number::from_f64(f64::NAN).is_none() && serde_json::Number::from_f64(f64::INFINITY).is_none());
        let p = clean_personality(&json!({"energy": u64::MAX, "curiosity": -5, "chatty": 1e300, "affection": -0.0, "sass": "0.9", "mischief": true}));
        let got: Vec<f64> = TRAIT_KEYS.iter().map(|k| p[*k].as_f64().unwrap()).collect();
        assert_eq!(got, [1.0, 0.0, 1.0, 0.0, 0.5, 0.5]);
        assert!(p["affection"].as_f64().unwrap().is_sign_positive(), "minus zero is stored as 0");
        assert_eq!(p["preset"], "custom");
    }

    #[test]
    fn a_preset_name_is_kept_only_while_the_traits_are_still_that_presets() {
        let chill = json!({"preset": "chill", "energy": 0.12, "curiosity": 0.35, "chatty": 0.3, "affection": 0.65, "sass": 0.3, "mischief": 0.2});
        assert_eq!(clean_personality(&chill)["preset"], "chill");
        let mut moved = chill.clone();
        moved["energy"] = json!(0.9);
        assert_eq!(clean_personality(&moved)["preset"], "custom");
        assert_eq!(clean_personality(&json!({"preset": "chill"}))["preset"], "custom", "a name alone: the traits are missing, so 0.5");
        assert_eq!(clean_personality(&json!({"preset": "balanced"}))["preset"], "balanced");
        assert_eq!(clean_personality(&Value::String(chill.to_string()))["preset"], "chill", "the Mac stores JSON text; so can a file");
        assert_eq!(clean_personality(&json!("{\"energy\":")), balanced(), "text that is not JSON");
        assert_eq!(clean_personality(&json!("[1,2]")), balanced(), "JSON that is not an object");
        let deep = format!("{}1{}", "[".repeat(5000), "]".repeat(5000));
        assert_eq!(clean_personality(&Value::String(deep)), balanced(), "nesting past serde_json's limit is an error, not a stack overflow");
    }

    /// Everything a clean value promises.
    fn valid(s: &Value) -> bool {
        let Some(o) = s.as_object() else { return false };
        let is = |k: &str, list: &[&str]| o.get(k).and_then(Value::as_str).is_some_and(|w| list.contains(&w));
        let with_follow = |list: &[&'static str]| -> Vec<&'static str> { list.iter().copied().chain([FOLLOW]).collect() };
        let (motions, collars) = (with_follow(&MOTION_STYLES), with_follow(&COLLAR_STYLES));
        let entry_ok = |e: &Value| {
            let Some(e) = e.as_object() else { return false };
            let word_ok = |k: &str, list: &[&str]| e.get(k).and_then(Value::as_str).is_some_and(|w| list.contains(&w));
            let Some(p) = e.get("personality").and_then(Value::as_object) else { return false };
            let preset = p.get("preset").and_then(Value::as_str).unwrap_or("");
            word_ok("motion", &motions)
                && word_ok("collar", &collars)
                && (preset == "custom" || PERSONAS.iter().any(|(n, _)| *n == preset))
                && TRAIT_KEYS.iter().all(|k| p.get(*k).and_then(Value::as_f64).is_some_and(|x| (0.0..=1.0).contains(&x)))
        };
        is("character", &CAT_IDS)
            && is("motionStyle", &MOTION_STYLES)
            && is("collar", &COLLAR_STYLES)
            && o.get("furLines").is_some_and(Value::is_boolean)
            && o.get("cats").and_then(Value::as_object).is_some_and(|c| c.keys().map(String::as_str).eq(CAT_IDS) && c.values().all(entry_ok))
    }

    #[test]
    fn hostile_values_never_panic_come_out_valid_and_cleaning_twice_changes_nothing() {
        let pool = vec![
            json!("momo"), json!("tiger"), json!("classic"), json!("playful"), json!("follow"), json!("off"), json!("band"), json!("tag"), json!("kerchief"),
            json!(""), json!(" "), json!("chill"), json!("custom"), json!("{"), json!("{\"energy\":2}"), json!("__proto__"), json!("constructor"),
            Value::String(json!({"preset":"sweet","affection":1,"energy":0.5,"curiosity":0.55,"chatty":0.55,"sass":0.1,"mischief":0.3}).to_string()),
            Value::Null, json!(true), json!(false), json!(0), json!(1), json!(-1), json!(0.5), json!(7), json!(1e300), json!(u64::MAX), json!([]), json!([1]), json!({}),
            json!({"energy": 9}), json!({"preset": "hyper"}),
        ];
        let mut state: u32 = 2026;
        let mut next = move || {
            state = state.wrapping_mul(1_103_515_245).wrapping_add(12_345);
            (state >> 8) as usize
        };
        for _ in 0..600 {
            let pick = |n: usize| pool[n % pool.len()].clone();
            let cats = if next() % 10 == 0 {
                pick(next())
            } else {
                let mut m = Map::new();
                for id in CAT_IDS {
                    if next() % 2 == 0 {
                        m.insert(id.into(), if next() % 10 == 0 { pick(next()) } else { json!({"motion": pick(next()), "collar": pick(next()), "personality": pick(next())}) });
                    }
                }
                Value::Object(m)
            };
            let raw = json!({"character": pick(next()), "motionStyle": pick(next()), "collar": pick(next()), "furLines": pick(next()), "cats": cats});
            let out = clean_cat_settings(&raw);
            assert!(valid(&out), "{raw}");
            assert_eq!(clean_cat_settings(&out), out, "{raw}");
        }
        for raw in [Value::Null, json!(5), json!("junk"), json!([]), json!({}), json!({"cats": []}), json!({"cats": "x"})] {
            assert_eq!(clean_cat_settings(&raw), default_value(), "{raw}");
        }
        let evil: Value = serde_json::from_str(r#"{"__proto__":{"motion":"classic"},"cats":{"__proto__":{"motion":"classic"},"constructor":{"motion":"classic"}}}"#).unwrap();
        let out = clean_cat_settings(&evil);
        assert!(valid(&out) && out["cats"].as_object().unwrap().len() == 16);
    }

    // ── The Display settings ──────────────────────────────────────────────────────────────────────────────────────────────────────────────

    #[test]
    fn the_display_frozen_values_are_the_fixtures() {
        let fx = fixture("display-cases.json");
        assert_eq!(fx["modes"], json!(DISPLAY_MODES));
        assert_eq!(fx["defaultPair"], json!(DEFAULT_PAIR));
        assert_eq!(fx["defaultAgentCats"], json!({"integration_claude": "shrimpy", "agent_codex": "momo"}));
        assert_eq!(fx["maxAgentCats"], json!(MAX_AGENT_CATS));
        assert_eq!(fx["pillIdPattern"], "^[a-z][a-z0-9_-]{1,63}$");
        assert_same(&clean_display_settings(&Value::Null), &fx["defaults"], "defaults");
    }

    #[test]
    fn every_display_case_of_the_fixture_replays() {
        let fx = fixture("display-cases.json");
        let (cases, pairs, agents, ids) = (fx["cases"].as_array().unwrap(), fx["pairs"].as_array().unwrap(), fx["agentCats"].as_array().unwrap(), fx["pillIds"].as_array().unwrap());
        assert!(cases.len() >= 30 && pairs.len() >= 40 && agents.len() >= 21 && ids.len() >= 29);
        for c in cases {
            assert_same(&clean_display_settings(&c["raw"]), &c["out"], c["name"].as_str().unwrap());
        }
        for c in pairs {
            assert_same(&json!(clean_pair(&c["raw"])), &c["out"], c["name"].as_str().unwrap());
        }
        for c in agents {
            assert_same(&clean_agent_cats(&c["raw"]), &c["out"], c["name"].as_str().unwrap());
        }
        for c in ids {
            let id = c["id"].as_str().unwrap();
            let got = json!({"id": id, "pill": is_pill_id(id), "agent": is_agent_pill(id), "default": default_agent_cat(id)});
            assert_eq!(&got, c, "{id:?}");
        }
    }

    #[test]
    fn a_pill_id_is_the_whole_string_and_never_a_prototype_name() {
        for bad in ["agent_x\n", "agent_x ", "agent_x\r\n", "\nagent_x", "agent_é", "Agent_x", "_agent", "a", "", "constructor", "prototype", "__proto__"] {
            assert!(!is_pill_id(bad), "{bad:?}");
        }
        assert!(is_pill_id("agent_x") && is_pill_id(&format!("a{}", "b".repeat(63))) && !is_pill_id(&format!("a{}", "b".repeat(64))));
        assert!(is_agent_pill("integration_claude") && is_agent_pill("agent_x") && !is_agent_pill("agent_") && !is_agent_pill("integration_stripe"));
    }

    #[test]
    fn the_desktop_clean_up_replays_the_fixture() {
        let fx = fixture("desktop-cases.json");
        let keys = fx["isScreenKey"].as_array().unwrap();
        assert!(keys.len() >= 30);
        for c in keys {
            assert_eq!(c["key"].as_str().map(is_screen_key).unwrap_or(false), c["out"].as_bool().unwrap(), "key {}", c["key"]);
        }
        let cases = fx["settingsCases"].as_array().unwrap();
        assert!(cases.len() >= 41);
        for c in cases {
            assert_same(&clean_desktop_settings(&c["raw"]), &c["out"], c["name"].as_str().unwrap());
        }
        for c in fx["spotMaps"].as_array().unwrap() {
            assert_same(&clean_desktop_spots(&c["raw"]), &c["out"], c["name"].as_str().unwrap());
        }
        assert_same(&clean_desktop_settings(&Value::Null), &fx["settingsDefaults"], "defaults");
        let sizes: Vec<&str> = fx["sizeIds"].as_array().unwrap().iter().map(|v| v.as_str().unwrap()).collect();
        assert_eq!(sizes, DESKTOP_SIZES);
        assert_eq!(fx["maxSpots"].as_u64(), Some(MAX_DESKTOP_SPOTS as u64));
    }

    #[test]
    fn the_desktop_spots_keep_the_first_32_in_code_point_order_and_hostile_input_never_panics() {
        let mut many = Map::new();
        for i in (0..300).rev() {
            many.insert(format!("{i},0,100,100"), json!({"x": i, "y": i}));
        }
        let out = clean_desktop_spots(&Value::Object(many));
        let keys: Vec<&String> = out.as_object().unwrap().keys().collect();
        assert_eq!(keys.len(), MAX_DESKTOP_SPOTS);
        let mut sorted = keys.clone();
        sorted.sort();
        assert_eq!(keys, sorted, "code-point order");
        for raw in [
            json!(null), json!(5), json!("{not json"), json!("[1]"), json!([1]), json!({"__proto__": {"x": 1, "y": 1}}),
            json!({"0,0,1,1": {"x": "1", "y": 2}}), json!({"0,0,1,1": {"x": 1e300, "y": 2}}), json!({"0,0,1,1": [1, 2]}), json!({"-0,0,1,1": {"x": 1, "y": 2}}),
            json!({"0,0,1512,982\n": {"x": 1, "y": 2}}), json!({"007,0,10,10": {"x": 1, "y": 2}}), json!({"0,0,0,10": {"x": 1, "y": 2}}), json!({"5,0,1,1|0,0,1,1": {"x": 1, "y": 2}}),
        ] {
            assert_eq!(clean_desktop_spots(&raw), json!({}), "{raw}");
        }
        assert_eq!(clean_desktop_spots(&json!("{\"0,0,1512,982\":{\"x\":3,\"y\":4,\"z\":5}}")), json!({"0,0,1512,982": {"x": 3, "y": 4}}), "the Mac's JSON text, reduced to x and y");
        assert_eq!(clean_desktop_settings(&json!({"on": "true", "size": "XL"})), json!({"on": false, "size": "medium", "spots": {}}));
        assert_eq!(clean_desktop_settings(&json!({"on": 1})), clean_desktop_settings(&Value::Null));
        assert_eq!(clean_desktop_settings(&json!({"on": true, "size": "large", "extra": 1})), json!({"on": true, "size": "large", "spots": {}}));
        for raw in [json!(null), json!(5), json!([]), json!("x")] {
            assert_eq!(clean_desktop_settings(&raw), clean_desktop_settings(&Value::Null), "{raw}");
        }
    }

    #[test]
    fn the_wardrobe_clean_up_replays_the_fixture() {
        let fx = fixture("wardrobe-cases.json");
        let ids: Vec<&str> = fx["ids"].as_array().unwrap().iter().map(|v| v.as_str().unwrap()).collect();
        assert_eq!(ids, OUTFIT_IDS);
        assert_eq!(fx["defaultOutfit"], "auto");
        let clean = fx["clean"].as_array().unwrap();
        assert!(clean.len() >= 38);
        for c in clean {
            assert_eq!(clean_wardrobe_settings(&json!({ "outfit": c["input"] }))["outfit"], c["out"], "{}", c["name"]);
        }
        let settings = fx["settings"].as_array().unwrap();
        assert!(settings.len() >= 11);
        for c in settings {
            assert_same(&clean_wardrobe_settings(&c["input"]), &c["out"], c["name"].as_str().unwrap());
        }
        assert_eq!(clean_wardrobe_settings(&Value::Null), json!({"outfit": "auto"}));
        for id in OUTFIT_IDS {
            assert_eq!(clean_wardrobe_settings(&json!({"outfit": id})), json!({"outfit": id}), "{id}");
        }
    }

    #[test]
    fn the_whole_block_holds_the_outfit_and_every_clean_up_of_the_block_keeps_it() {
        let raw = json!({"character": "momo", "displayMode": "two", "desktop": {"on": true}, "outfit": "crown"});
        let block = clean_cat_block(&raw);
        assert_eq!((&block["outfit"], &block["character"], &block["displayMode"], &block["desktop"]["on"]), (&json!("crown"), &json!("momo"), &json!("two"), &json!(true)));
        assert_eq!(clean_cat_block(&block), block, "cleaning twice changes nothing");
        assert_eq!(block_default()["outfit"], "auto");
        for bad in [json!(7), json!(null), json!(true), json!([]), json!(["bow"]), json!({}), json!("Bow"), json!(" bow"), json!("bow\n"), json!("party-hat"), json!("")] {
            assert_eq!(clean_cat_block(&json!({"character": "momo", "outfit": bad}))["outfit"], "auto", "{bad}");
        }
        assert!(clean_cat_settings(&raw).get("outfit").is_none(), "the Cat settings clean-up alone drops it: that is why the block has a clean-up of its own");
        assert!(clean_display_settings(&raw).get("outfit").is_none());
        assert!(clean_desktop_settings(&raw).get("outfit").is_none());
    }

    #[test]
    fn the_whole_block_holds_the_desktop_settings_and_cleaning_it_twice_changes_nothing() {
        let raw = json!({"character": "momo", "displayMode": "two", "desktop": {"on": true, "size": "small", "spots": {"0,0,1512,982": {"x": 300, "y": 400}}}});
        let block = clean_cat_block(&raw);
        assert_eq!(block["desktop"], json!({"on": true, "size": "small", "spots": {"0,0,1512,982": {"x": 300, "y": 400}}}));
        assert_eq!((&block["character"], &block["displayMode"]), (&json!("momo"), &json!("two")));
        assert_eq!(clean_cat_block(&block), block);
        assert_eq!(block_default()["desktop"], json!({"on": false, "size": "medium", "spots": {}}));
        assert!(clean_cat_settings(&raw).get("desktop").is_none(), "the Cat settings clean-up alone drops it: that is why the block has a clean-up of its own");
        assert!(clean_display_settings(&raw).get("desktop").is_none());
    }

    #[test]
    fn the_whole_block_keeps_both_parts_and_a_clean_up_with_the_cat_settings_alone_drops_the_display_keys() {
        let raw = json!({"character": "momo", "collar": "band", "displayMode": "two", "pair": ["ginger", "latte"], "agentCats": {"agent_gemini": "oreo", "constructor": "momo"}});
        let block = clean_cat_block(&raw);
        assert_eq!(block["character"], "momo");
        assert_eq!(block["displayMode"], "two");
        assert_eq!(block["pair"], json!(["ginger", "latte"]));
        assert_eq!(block["agentCats"], json!({"agent_gemini": "oreo"}));
        assert_eq!(block["cats"].as_object().unwrap().len(), 16);
        assert!(clean_cat_settings(&raw).get("displayMode").is_none(), "that is why the block has a clean-up of its own");
        assert_eq!(clean_cat_block(&block), block, "cleaning twice changes nothing");
        assert_eq!(block_default()["displayMode"], "one");
        assert_eq!(block_default()["pair"], json!(["shrimpy", "momo"]));
        assert_eq!(block_default()["agentCats"], json!({}));
        assert_same(&clean_cat_settings(&block_default()), &fixture("settings-cases.json")["defaults"], "the Cat part of the default block");
        assert_eq!(clean_cat_block(&json!(5)), block_default());
    }

    #[test]
    fn hostile_display_values_never_panic_come_out_valid_and_cleaning_twice_changes_nothing() {
        let pool = vec![
            json!("one"), json!("two"), json!("perAgent"), json!("Two"), json!(""), json!(" "), json!("momo"), json!("tiger"), json!("[\"momo\",\"ginger\"]"), json!("[\"momo\""),
            json!("__proto__"), json!("constructor"), json!("agent_x"), json!("agent_codex"), json!("integration_claude"), Value::Null, json!(true), json!(0), json!(-1), json!(0.5), json!(7),
            json!(u64::MAX), json!([]), json!(["momo"]), json!(["momo", "ginger"]), json!(["ginger", "ginger"]), json!([1, 2]), json!({}), json!({"agent_x": "latte"}), json!({"agent_codex": "tiger"}),
        ];
        let mut state: u32 = 2027;
        let mut next = move || {
            state = state.wrapping_mul(1_103_515_245).wrapping_add(12_345);
            (state >> 8) as usize
        };
        for _ in 0..600 {
            let pick = |n: usize| pool[n % pool.len()].clone();
            let agents = if next() % 6 == 0 {
                pick(next())
            } else {
                let mut m = Map::new();
                for _ in 0..next() % 6 {
                    if let Some(k) = pick(next()).as_str() {
                        m.insert(k.to_string(), pick(next()));
                    }
                }
                Value::Object(m)
            };
            let raw = json!({"displayMode": pick(next()), "pair": pick(next()), "agentCats": agents});
            let out = clean_display_settings(&raw);
            let pair: Vec<&str> = out["pair"].as_array().unwrap().iter().map(|v| v.as_str().unwrap()).collect();
            assert!(DISPLAY_MODES.contains(&out["displayMode"].as_str().unwrap()) && pair.len() == 2 && pair.iter().all(|c| CAT_IDS.contains(c)) && pair[0] != pair[1], "{raw}");
            let keys: Vec<&String> = out["agentCats"].as_object().unwrap().keys().collect();
            let mut sorted = keys.clone();
            sorted.sort();
            assert!(keys == sorted && keys.len() <= MAX_AGENT_CATS && keys.iter().all(|k| is_pill_id(k)), "{raw}");
            assert!(out["agentCats"].as_object().unwrap().values().all(|v| cat_id(v).is_some()), "{raw}");
            assert_eq!(clean_display_settings(&out), out, "{raw}");
        }
        for raw in [Value::Null, json!(5), json!("junk"), json!([]), json!({}), json!({"pair": 7, "agentCats": 7, "displayMode": 7})] {
            assert_eq!(clean_display_settings(&raw), clean_display_settings(&Value::Null), "{raw}");
        }
        let evil: Value = serde_json::from_str(r#"{"agentCats":{"__proto__":"momo","constructor":"momo","prototype":"momo","agent_ok":"ginger"}}"#).unwrap();
        assert_eq!(clean_display_settings(&evil)["agentCats"], json!({"agent_ok": "ginger"}));
        let many: Map<String, Value> = (0..300).map(|i| (format!("agent_a{i:03}"), json!(CAT_IDS[i % 16]))).collect();
        let out = clean_agent_cats(&Value::Object(many));
        let keys: Vec<&String> = out.as_object().unwrap().keys().collect();
        assert_eq!((keys.len(), keys[0].as_str(), keys[255].as_str()), (256, "agent_a000", "agent_a255"), "300 pills keep the first 256");
    }

    // ── The project cats (sub-project P) ────────────────────────────────────────────────────────────────────────────────────────────────

    fn projects_fixture(name: &str) -> Value {
        let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../tests/fixtures/projects").join(name);
        let text = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
        serde_json::from_str(&text).unwrap_or_else(|e| panic!("parse {}: {e}", path.display()))
    }

    #[test]
    fn the_project_cats_clean_up_replays_cat_cases() {
        let fx = projects_fixture("cat-cases.json");
        let cases = fx["clean"].as_array().unwrap();
        assert_eq!(cases.len(), 9);
        for c in cases {
            assert_same(&clean_project_cats(&c["raw"]), &c["expect"], c["name"].as_str().unwrap());
        }
    }

    #[test]
    fn the_project_cats_keep_the_first_256_in_utf16_order() {
        let many: Map<String, Value> = (0..300).map(|i| (format!("k{i:03}"), json!("momo"))).collect();
        let out = clean_project_cats(&Value::Object(many));
        let keys: Vec<&String> = out.as_object().unwrap().keys().collect();
        assert_eq!((keys.len(), keys[0].as_str(), keys[255].as_str()), (256, "k000", "k255"), "300 projects keep the first 256");
        assert_eq!(utf16_sorted(vec!["\u{FF5E}", "\u{1F600}"]), ["\u{1F600}", "\u{FF5E}"], "UTF-16 code-unit order, not byte order");
    }

    #[test]
    fn a_project_key_with_an_invisible_character_is_dropped() {
        let raw = json!({"a\u{200B}b": "momo", "a\u{202E}b": "momo", "a\u{E0001}b": "momo", "ab": "momo"});
        assert_eq!(clean_project_cats(&raw), json!({"ab": "momo"}));
    }

    #[test]
    fn the_block_holds_project_cats() {
        let block = clean_cat_block(&json!({"projectCats": {"notchmeow": "oreo", "a/b": "momo", "x": "tiger"}}));
        assert_eq!(block["projectCats"], json!({"notchmeow": "oreo"}));
        assert_eq!(block_default()["projectCats"], json!({}));
        assert_eq!(clean_cat_block(&block), block, "cleaning twice changes nothing");
    }
}
