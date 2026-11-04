// The shelf (sub-project G1): files parked in the notch. Two halves in this file:
//
//  1. The contract's rules in Rust (`clean`, `add_values`, `read`), the twin of src/shelf/rules.ts. Both replay tests/fixtures/shelf/ (docs/SHELF-CONTRACT.md);
//     tests/fixtures/shelf/reference.py is the tie-breaker. `zoneAt` is not here: the page decides the half.
//  2. The store: `shelf.json` and the copies under the app's data folder. The page holds ids, and every command that touches a file takes an id. The one exception is
//     shelf_ask's success value (lib.rs), a DroppedFile whose `path` is the inbox path the file was copied to.
//
// Nothing here runs unless the user does something (a drop on the Shelf half, a click): no timer, no watcher, no poll. Whether the files still exist is looked at only when
// the shelf is listed (it opens), when a drop or a Remove returns the list, and when an item is resolved (Ask, a drag out, a share).

use std::path::{Component, Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

use serde::Serialize;
use serde_json::Value;

pub const MAX: usize = 30;
const NAME_MAX: usize = 255;
const LINK_MAX: usize = 8192;
const NUMBER_MAX: u64 = 9_007_199_254_740_991;
const ID_MAX: usize = 64;
/// What a shelf add that fails says, and all it says: no path, no name, no id.
const ADD_FAILED: &str = "shelf add failed";

/// One thing on the shelf, as the contract's `shelfClean` leaves it (fields in the contract's order). A copy has no link.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Item {
    pub id: String,
    pub name: String,
    pub size: u64,
    pub folder: bool,
    pub copy: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub link: Option<String>,
    pub added_at: u64,
}

// ── The rules ─────────────────────────────────────────────────────────────────

/// Unicode category Cf (format characters: the bidi controls, the zero-width space, the byte order mark). Rust's standard library has no table for it.
const FORMAT_RANGES: &[(u32, u32)] = &[
    (0x00AD, 0x00AD), (0x0600, 0x0605), (0x061C, 0x061C), (0x06DD, 0x06DD), (0x070F, 0x070F), (0x0890, 0x0891), (0x08E2, 0x08E2), (0x180E, 0x180E),
    (0x200B, 0x200F), (0x202A, 0x202E), (0x2060, 0x2064), (0x2066, 0x206F), (0xFEFF, 0xFEFF), (0xFFF9, 0xFFFB), (0x110BD, 0x110BD), (0x110CD, 0x110CD),
    (0x13430, 0x1343F), (0x1BCA0, 0x1BCA3), (0x1D173, 0x1D17A), (0xE0001, 0xE0001), (0xE0020, 0xE007F),
];

fn is_format(c: char) -> bool {
    let n = c as u32;
    FORMAT_RANGES.iter().any(|&(lo, hi)| n >= lo && n <= hi)
}

/// A name may not hold a control (Cc), a format character (Cf), a line or paragraph separator (Zl, Zp). (A lone surrogate, Cs, cannot be held by a Rust string at all.)
fn bad_name_char(c: char) -> bool {
    c.is_control() || is_format(c) || c == '\u{2028}' || c == '\u{2029}'
}

const RESERVED: &[&str] = &[
    "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
    "COM\u{b9}", "COM\u{b2}", "COM\u{b3}", "LPT\u{b9}", "LPT\u{b2}", "LPT\u{b3}",
];

/// A Windows device name as the stem (the part before the first dot, trailing spaces trimmed), ASCII case-insensitively.
fn reserved(s: &str) -> bool {
    let stem = s.split('.').next().unwrap_or("").trim_end_matches(' ').to_ascii_uppercase();
    RESERVED.contains(&stem.as_str())
}

fn name_ok(name: &str) -> bool {
    let n = name.chars().count();
    if !(1..=NAME_MAX).contains(&n) {
        return false;
    }
    if name.chars().any(bad_name_char) || name.contains('/') || name.contains('\\') || name.chars().all(|c| c == '.') || name.ends_with('.') || name.ends_with(' ') {
        return false;
    }
    !reserved(name)
}

fn id_ok(id: &str) -> bool {
    (1..=ID_MAX).contains(&id.len()) && id.chars().all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-') && !reserved(id)
}

/// A whole number from 0 to 2^53 - 1 (5 and 5.0 are the same JSON number), else 0.
fn whole(v: Option<&Value>) -> u64 {
    let Some(Value::Number(n)) = v else { return 0 };
    if let Some(u) = n.as_u64() {
        return if u <= NUMBER_MAX { u } else { 0 };
    }
    match n.as_f64() {
        Some(f) if f.is_finite() && f.fract() == 0.0 && f >= 0.0 && f <= NUMBER_MAX as f64 => f as u64,
        _ => 0,
    }
}

fn item_clean(raw: &Value) -> Option<Item> {
    let o = raw.as_object()?;
    let id = o.get("id")?.as_str()?;
    let name = o.get("name")?.as_str()?;
    if !id_ok(id) || !name_ok(name) {
        return None;
    }
    let copy = o.get("copy") == Some(&Value::Bool(true));
    let folder = o.get("folder") == Some(&Value::Bool(true));
    if copy && folder {
        return None; // a folder is only ever a link
    }
    let link = if copy {
        None
    } else {
        let link = o.get("link")?.as_str()?;
        let n = link.chars().count();
        if !(1..=LINK_MAX).contains(&n) || link.chars().any(|c| c.is_control()) {
            return None;
        }
        Some(link.to_string())
    };
    Some(Item { id: id.to_string(), name: name.to_string(), size: whole(o.get("size")), folder, copy, link, added_at: whole(o.get("addedAt")) })
}

/// Newest first (stable), then the first of each id (ASCII case-insensitive) and of each link (exact), then the first MAX. One pass in sorted order.
fn tidy(mut items: Vec<Item>) -> Vec<Item> {
    items.sort_by(|a, b| b.added_at.cmp(&a.added_at));
    let mut ids = std::collections::HashSet::new();
    let mut links = std::collections::HashSet::new();
    let mut out = Vec::new();
    for it in items {
        let key = it.id.to_ascii_lowercase();
        if ids.contains(&key) || it.link.as_ref().is_some_and(|l| links.contains(l)) {
            continue;
        }
        ids.insert(key);
        if let Some(l) = &it.link {
            links.insert(l.clone());
        }
        out.push(it);
    }
    out.truncate(MAX);
    out
}

/// The parsed content of shelf.json to the items the shelf holds. Never panics.
pub fn clean(raw: &Value) -> Vec<Item> {
    let Some(items) = raw.get("items").and_then(Value::as_array) else { return Vec::new() };
    tidy(items.iter().filter_map(item_clean).collect())
}

/// The result of one incoming item in a drop on the Shelf half.
pub type Word = &'static str;

/// Files dropped on the Shelf half: the new shelf and one word per incoming item (`added`, `duplicate`, `full` or `invalid`). Nothing already shelved is ever removed.
pub fn add_values(items: &Value, incoming: &Value) -> (Vec<Item>, Vec<Word>) {
    let current = clean(&serde_json::json!({ "items": items }));
    let mut ids: std::collections::HashSet<String> = current.iter().map(|i| i.id.to_ascii_lowercase()).collect();
    let mut links: std::collections::HashSet<String> = current.iter().filter_map(|i| i.link.clone()).collect();
    let mut accepted: Vec<Item> = Vec::new();
    let mut results: Vec<Word> = Vec::new();
    for raw in incoming.as_array().map(Vec::as_slice).unwrap_or(&[]) {
        match item_clean(raw) {
            None => results.push("invalid"),
            Some(it) if ids.contains(&it.id.to_ascii_lowercase()) || it.link.as_ref().is_some_and(|l| links.contains(l)) => results.push("duplicate"),
            Some(_) if current.len() + accepted.len() >= MAX => results.push("full"),
            Some(it) => {
                ids.insert(it.id.to_ascii_lowercase());
                if let Some(l) = &it.link {
                    links.insert(l.clone());
                }
                accepted.push(it);
                results.push("added");
            }
        }
    }
    accepted.extend(current);
    (tidy(accepted), results)
}

/// A JSON text with every lone surrogate escape (`\ud800` not followed by a low one, or a low one on its own) replaced by `\u0000`. serde_json refuses the whole file for one;
/// the contract keeps the other items, and an item with a control character in its name or link is dropped, which is what a lone surrogate there does.
pub fn neutralize_lone_surrogates(text: &str) -> String {
    let chars: Vec<char> = text.chars().collect();
    let hex4 = |at: usize| -> Option<u32> {
        let s: String = chars.get(at..at + 4)?.iter().collect();
        if s.len() == 4 && s.chars().all(|c| c.is_ascii_hexdigit()) { u32::from_str_radix(&s, 16).ok() } else { None }
    };
    let mut out = String::with_capacity(text.len());
    let (mut i, mut in_string) = (0, false);
    while i < chars.len() {
        let c = chars[i];
        if in_string && c == '\\' && i + 1 < chars.len() {
            if chars[i + 1] == 'u' {
                if let Some(unit) = hex4(i + 2) {
                    let high = (0xD800..0xDC00).contains(&unit);
                    let low = (0xDC00..0xE000).contains(&unit);
                    let pair = high && chars.get(i + 6) == Some(&'\\') && chars.get(i + 7) == Some(&'u') && hex4(i + 8).is_some_and(|u| (0xDC00..0xE000).contains(&u));
                    if pair {
                        out.extend(&chars[i..i + 12]);
                        i += 12;
                    } else if high || low {
                        out.push_str("\\u0000");
                        i += 6;
                    } else {
                        out.extend(&chars[i..i + 6]);
                        i += 6;
                    }
                    continue;
                }
            }
            out.push(c);
            out.push(chars[i + 1]);
            i += 2;
            continue;
        }
        if c == '"' {
            in_string = !in_string;
        }
        out.push(c);
        i += 1;
    }
    out
}

/// The value of a shelf file's bytes, strictly: UTF-8 (a byte order mark is not stripped), no NaN or Infinity, nothing after the value. None when unreadable.
fn parse_strict(bytes: &[u8]) -> Option<Value> {
    let text = std::str::from_utf8(bytes).ok()?;
    serde_json::from_str(&neutralize_lone_surrogates(text)).ok()
}

/// The bytes of shelf.json to the items it holds. Unreadable bytes are an empty shelf. Never panics.
pub fn read(bytes: &[u8]) -> Vec<Item> {
    parse_strict(bytes).map(|v| clean(&v)).unwrap_or_default()
}

// ── The store ─────────────────────────────────────────────────────────────────

/// What the page gets for one item: no link (it is never shown, and the page never needs a path), and whether the original is gone.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Entry {
    pub id: String,
    pub name: String,
    pub size: u64,
    pub folder: bool,
    pub copy: bool,
    pub added_at: u64,
    pub missing: bool,
}

/// One writer at a time: a drop and a Remove in the same instant cannot lose each other's change.
static LOCK: Mutex<()> = Mutex::new(());
static COUNTER: AtomicU64 = AtomicU64::new(0);

fn new_id() -> String {
    let nanos = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_nanos()).unwrap_or(0);
    format!("s{:x}{:x}", nanos, COUNTER.fetch_add(1, Ordering::Relaxed))
}

fn now_ms() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as u64).unwrap_or(0)
}

pub struct Store {
    root: PathBuf,
}

impl Store {
    /// `root` is the app's data folder: `shelf.json` lives in it and copies under `shelf/<id>/<name>`.
    pub fn new(root: PathBuf) -> Store {
        Store { root }
    }

    fn file(&self) -> PathBuf {
        self.root.join("shelf.json")
    }

    fn copies(&self) -> PathBuf {
        self.root.join("shelf")
    }

    pub fn load(&self) -> Vec<Item> {
        std::fs::read(self.file()).map(|b| read(&b)).unwrap_or_default()
    }

    /// Writes the list. Before it overwrites a file it could not read, or one that held items the clean-up drops (a hand-edited or damaged file), the old bytes are kept as
    /// `shelf.json.bad-<ms>` (the contract). The write goes to a temporary file first, so a crash leaves the old file or the new one, never half of one.
    fn save(&self, items: &[Item]) -> std::io::Result<()> {
        std::fs::create_dir_all(&self.root)?;
        let file = self.file();
        // Only "no file yet" lets the write go ahead without a look at the old bytes. Any other read error stops the save, so the old file is not overwritten.
        let old = match std::fs::read(&file) {
            Ok(old) => Some(old),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => None,
            Err(e) => return Err(e),
        };
        if let Some(old) = old {
            let lossy = match parse_strict(&old) {
                None => !old.is_empty(),
                // A top-level value that is not an object (an array, null, text, a number) is unreadable as a shelf, so its bytes are kept.
                Some(v) if !v.is_object() => true,
                Some(v) => {
                    let clean_len = clean(&v).len();
                    let raw_len = v.get("items").and_then(Value::as_array).map(Vec::len).unwrap_or(0);
                    // An "items" that is present but not a list is not a shelf either: its bytes are kept too.
                    raw_len > clean_len || v.get("items").is_some_and(|i| !i.is_array())
                }
            };
            if lossy {
                std::fs::write(self.root.join(format!("shelf.json.bad-{}", now_ms())), &old)?;
            }
        }
        let body = serde_json::to_vec(&serde_json::json!({ "version": 1, "items": items }))?;
        let tmp = self.root.join("shelf.json.tmp");
        std::fs::write(&tmp, body)?;
        std::fs::rename(&tmp, &file)
    }

    /// Where the item's file is: a copy under `shelf/<id>/<name>`, otherwise its original. None for a link that is not an absolute path.
    pub fn path_of(&self, item: &Item) -> Option<PathBuf> {
        if item.copy {
            // Exactly one normal name: an absolute path, `..`, `./x` or `a/b` would leave the item's folder. Anything else is None (missing).
            let mut parts = Path::new(&item.name).components();
            return match (parts.next(), parts.next()) {
                (Some(Component::Normal(name)), None) => Some(self.copies().join(&item.id).join(name)),
                _ => None,
            };
        }
        let p = PathBuf::from(item.link.as_ref()?);
        p.is_absolute().then_some(p)
    }

    fn entries_of(&self, items: &[Item]) -> Vec<Entry> {
        items
            .iter()
            .map(|i| Entry {
                id: i.id.clone(),
                name: i.name.clone(),
                size: i.size,
                folder: i.folder,
                copy: i.copy,
                added_at: i.added_at,
                missing: self.path_of(i).map(|p| !p.exists()).unwrap_or(true),
            })
            .collect()
    }

    /// The shelf as it opens: every item, with whether its original is gone. add_paths and remove return the same list and look at the files the same way; resolve looks at the ones it is asked for.
    pub fn entries(&self) -> Vec<Entry> {
        self.entries_of(&self.load())
    }

    /// The files of a Shelf drop. An item is built for each path that is an absolute path to something that exists with a name the contract allows; the rest are `invalid`.
    /// A failure says `ADD_FAILED` only: the OS text of a failed write is not the page's to show, and it never names a file.
    pub fn add_paths(&self, paths: &[String]) -> Result<(Vec<Entry>, Vec<Word>), &'static str> {
        let _guard = LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let now = now_ms();
        let incoming: Vec<Value> = paths
            .iter()
            .map(|p| {
                let path = Path::new(p);
                let meta = if path.is_absolute() { std::fs::metadata(path).ok() } else { None };
                let name = path.file_name().map(|n| n.to_string_lossy().to_string());
                match (meta, name) {
                    (Some(m), Some(name)) => serde_json::json!({
                        "id": new_id(), "name": name, "size": if m.is_dir() { 0 } else { m.len() },
                        "folder": m.is_dir(), "copy": false, "link": p, "addedAt": now,
                    }),
                    _ => Value::Null,
                }
            })
            .collect();
        let current = self.load();
        let (items, results) = add_values(&serde_json::to_value(&current).map_err(|_| ADD_FAILED)?, &Value::Array(incoming));
        if results.contains(&"added") {
            self.save(&items).map_err(|_| ADD_FAILED)?;
        }
        Ok((self.entries_of(&items), results))
    }

    /// Takes one item off the shelf and deletes its copy, if it has one. Originals are never touched. An unknown id changes nothing.
    pub fn remove(&self, id: &str) -> std::io::Result<Vec<Entry>> {
        let _guard = LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let current = self.load();
        let Some(gone) = current.iter().find(|i| i.id == id) else { return Ok(self.entries_of(&current)) };
        // The copy is deleted before save, so a failed save leaves the item listed with its copy missing.
        self.drop_copy(gone)?;
        let rest: Vec<Item> = current.iter().filter(|i| i.id != id).cloned().collect();
        self.save(&rest)?;
        Ok(self.entries_of(&rest))
    }

    /// Clear all: every copy goes, every original stays. An item whose copy cannot be removed stays listed; the rest are saved as removed, and the first error is returned after the save.
    pub fn clear(&self) -> std::io::Result<Vec<Entry>> {
        let _guard = LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let mut kept = Vec::new();
        let mut first_err = None;
        for item in self.load() {
            if let Err(e) = self.drop_copy(&item) {
                first_err.get_or_insert(e);
                kept.push(item);
            }
        }
        self.save(&kept)?;
        match first_err {
            Some(e) => Err(e),
            None => Ok(Vec::new()),
        }
    }

    /// A copy lives in its own folder, `shelf/<id>/`, and the id is the contract's `[A-Za-z0-9_-]{1,64}`, so the folder cannot leave `shelf/`.
    /// Called before the item leaves the list: a copy that cannot be removed is an error and the item stays listed. A copy already gone is not an error.
    fn drop_copy(&self, item: &Item) -> std::io::Result<()> {
        if !item.copy || !id_ok(&item.id) {
            return Ok(());
        }
        match std::fs::remove_dir_all(self.copies().join(&item.id)) {
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
            other => other,
        }
    }

    /// The files of these ids that exist, in the order asked (a drag out, a share, Show in folder). An id that is not on the shelf or whose file is gone is left out.
    pub fn resolve(&self, ids: &[String]) -> Vec<PathBuf> {
        let items = self.load();
        ids.iter().filter_map(|id| items.iter().find(|i| &i.id == id)).filter_map(|i| self.path_of(i)).filter(|p| p.exists()).collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    fn fixture(name: &str) -> Value {
        let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../tests/fixtures/shelf").join(name);
        let text = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
        serde_json::from_str(&neutralize_lone_surrogates(&text)).unwrap_or_else(|e| panic!("parse {}: {e}", path.display()))
    }

    fn as_value(items: &[Item]) -> Value {
        serde_json::to_value(items).unwrap()
    }

    fn temp(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("notchmeow-shelf-{tag}-{}-{}", std::process::id(), COUNTER.fetch_add(1, Ordering::Relaxed)));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn the_constants_are_the_fixtures() {
        let s = fixture("shelf-cases.json");
        assert_eq!(s["max"], MAX);
        assert_eq!(s["nameMax"], NAME_MAX);
        assert_eq!(s["linkMax"], LINK_MAX);
        assert_eq!(s["numberMax"], NUMBER_MAX);
        assert_eq!(s["idPattern"], format!("[A-Za-z0-9_-]{{1,{ID_MAX}}}"));
    }

    #[test]
    fn clean_replays_every_clean_case() {
        let s = fixture("shelf-cases.json");
        let cases = s["cleanCases"].as_array().unwrap();
        assert!(cases.len() >= 100);
        for c in cases {
            assert_eq!(as_value(&clean(&c["raw"])), c["out"], "{}", c["name"]);
        }
    }

    #[test]
    fn add_replays_every_add_case() {
        let s = fixture("shelf-cases.json");
        let cases = s["addCases"].as_array().unwrap();
        assert!(cases.len() >= 25);
        for c in cases {
            let (items, results) = add_values(&c["items"], &c["incoming"]);
            assert_eq!(serde_json::json!({ "items": items, "results": results }), c["out"], "{}", c["name"]);
        }
    }

    #[test]
    fn read_replays_every_parse_case() {
        let s = fixture("shelf-cases.json");
        let cases = s["parseCases"].as_array().unwrap();
        assert!(cases.len() >= 15);
        for c in cases {
            let bytes: Vec<u8> = match c.get("text").and_then(Value::as_str) {
                Some(t) => t.as_bytes().to_vec(),
                None => {
                    let hex = c["hex"].as_str().unwrap();
                    (0..hex.len()).step_by(2).map(|i| u8::from_str_radix(&hex[i..i + 2], 16).unwrap()).collect()
                }
            };
            assert_eq!(as_value(&read(&bytes)), c["out"], "{}", c["name"]);
        }
    }

    #[test]
    fn a_lone_surrogate_costs_one_item_not_the_shelf_and_a_pair_survives() {
        let (hi, lo) = (format!("{}ud83d", '\\'), format!("{}ude00", '\\'));
        let text = format!(
            r#"{{"items":[{{"id":"a","name":"x\ud800y","copy":true,"addedAt":2}},{{"id":"b","name":"ok{hi}{lo}","copy":true,"addedAt":1}},{{"id":"c","name":"c.txt","link":"back\\ud800slash","addedAt":0}}]}}"#
        );
        let got = read(text.as_bytes());
        assert_eq!(got.iter().map(|i| i.id.as_str()).collect::<Vec<_>>(), ["b", "c"]);
        assert_eq!(got[0].name, "ok\u{1F600}");
        assert_eq!(got[1].link.as_deref(), Some("back\\ud800slash"), "an escaped backslash is not an escape");
    }

    #[test]
    fn the_format_table_is_the_contracts_examples() {
        for c in ['\u{202E}', '\u{200B}', '\u{FEFF}', '\u{00AD}', '\u{2066}'] {
            assert!(is_format(c), "{c:?}");
        }
        for c in ['a', 'é', '\u{2028}', '\u{3000}', '\u{1F600}'] {
            assert!(!is_format(c), "{c:?}");
        }
    }

    #[test]
    fn adding_files_keeps_them_in_the_order_dropped_refuses_what_cannot_be_shelved_and_stops_at_thirty() {
        let root = temp("add");
        let data = temp("files");
        let store = Store::new(root.clone());
        let paths: Vec<String> = (0..32)
            .map(|n| {
                let p = data.join(format!("f{n}.txt"));
                std::fs::write(&p, vec![b'x'; n]).unwrap();
                p.to_string_lossy().to_string()
            })
            .collect();
        let dir = data.join("a folder");
        std::fs::create_dir_all(&dir).unwrap();

        let mut drop = vec![paths[0].clone(), "relative/file.txt".to_string(), data.join("gone.txt").to_string_lossy().to_string(), dir.to_string_lossy().to_string()];
        drop.push(paths[0].clone());
        let (entries, words) = store.add_paths(&drop).unwrap();
        assert_eq!(words, ["added", "invalid", "invalid", "added", "duplicate"]);
        assert_eq!(entries.len(), 2);
        assert!(entries.iter().any(|e| e.folder && e.name == "a folder" && e.size == 0));
        assert!(entries.iter().all(|e| !e.missing));

        let (entries, words) = store.add_paths(&paths[1..].to_vec()).unwrap();
        assert_eq!(entries.len(), MAX, "the cap holds");
        assert_eq!(words.iter().filter(|w| **w == "added").count(), MAX - 2);
        assert_eq!(words.iter().filter(|w| **w == "full").count(), 31 - (MAX - 2));
        assert!(std::fs::read_to_string(root.join("shelf.json")).unwrap().contains("\"version\":1"));
        assert_eq!(store.load().len(), MAX, "it survives a restart (a new Store reads the same file)");
        assert_eq!(Store::new(root).load().len(), MAX);
    }

    #[test]
    fn a_missing_original_shows_as_missing_and_remove_never_touches_an_original() {
        let root = temp("missing");
        let data = temp("orig");
        let store = Store::new(root);
        let file = data.join("note.txt");
        std::fs::write(&file, b"hello").unwrap();
        let (entries, _) = store.add_paths(&[file.to_string_lossy().to_string()]).unwrap();
        let id = entries[0].id.clone();
        assert_eq!(store.resolve(&[id.clone(), "nope".into()]), vec![file.clone()]);
        std::fs::remove_file(&file).unwrap();
        assert!(store.entries()[0].missing, "looked at when the shelf is listed");
        assert!(store.resolve(&[id.clone()]).is_empty());
        std::fs::write(&file, b"back").unwrap();
        assert!(!store.entries()[0].missing);
        let after = store.remove(&id).unwrap();
        assert!(after.is_empty());
        assert_eq!(std::fs::read(&file).unwrap(), b"back", "the original is never touched");
        assert!(store.remove("unknown").unwrap().is_empty());
    }

    #[test]
    fn a_copy_resolves_under_shelf_id_name_and_removing_it_deletes_only_its_folder() {
        let root = temp("copy");
        let store = Store::new(root.clone());
        let folder = root.join("shelf").join("c1");
        std::fs::create_dir_all(&folder).unwrap();
        std::fs::write(folder.join("pic.png"), b"png").unwrap();
        let keep = root.join("shelf").join("c2");
        std::fs::create_dir_all(&keep).unwrap();
        std::fs::write(keep.join("keep.txt"), b"k").unwrap();
        let text = r#"{"version":1,"items":[{"id":"c1","name":"pic.png","size":3,"copy":true,"addedAt":2},{"id":"c2","name":"keep.txt","size":1,"copy":true,"addedAt":1}]}"#;
        std::fs::write(root.join("shelf.json"), text).unwrap();
        assert_eq!(store.resolve(&["c1".into()]), vec![folder.join("pic.png")]);
        store.remove("c1").unwrap();
        assert!(!folder.exists());
        assert!(keep.join("keep.txt").exists());
        store.clear().unwrap();
        assert!(!keep.exists());
        assert!(store.load().is_empty());
    }

    #[test]
    fn an_unreadable_or_trimmed_file_is_kept_as_a_backup_before_it_is_overwritten() {
        let root = temp("bad");
        let data = temp("badfiles");
        let store = Store::new(root.clone());
        let file = data.join("a.txt");
        std::fs::write(&file, b"a").unwrap();
        let bad = |root: &Path| std::fs::read_dir(root).unwrap().flatten().filter(|e| e.file_name().to_string_lossy().starts_with("shelf.json.bad-")).count();

        std::fs::write(root.join("shelf.json"), b"{\"items\": [").unwrap();
        store.add_paths(&[file.to_string_lossy().to_string()]).unwrap();
        assert_eq!(bad(&root), 1, "a truncated file is kept");

        let mut raw: Vec<Value> = (0..40).map(|n| serde_json::json!({ "id": format!("h{n}"), "name": "n", "link": format!("/p/{n}"), "addedAt": n })).collect();
        raw.push(Value::Null);
        std::fs::write(root.join("shelf.json"), serde_json::to_vec(&serde_json::json!({ "items": raw })).unwrap()).unwrap();
        store.remove("h39").unwrap();
        assert_eq!(bad(&root), 2, "a file with more than the clean-up keeps is kept before the cap trims it");

        let n = bad(&root);
        store.remove("nothing").unwrap();
        store.clear().unwrap();
        store.add_paths(&[file.to_string_lossy().to_string()]).unwrap();
        assert_eq!(bad(&root), n, "a file the store itself wrote is clean, so it never makes a backup");
    }

    #[test]
    fn a_copy_that_cannot_be_removed_stays_listed() {
        let root = temp("stuck");
        let store = Store::new(root.clone());
        // The copy's folder is a plain file, so removing it fails: the item must stay on the shelf.
        std::fs::create_dir_all(root.join("shelf")).unwrap();
        std::fs::write(root.join("shelf").join("c1"), b"not a folder").unwrap();
        std::fs::write(root.join("shelf.json"), r#"{"version":1,"items":[{"id":"c1","name":"pic.png","size":3,"copy":true,"addedAt":2}]}"#).unwrap();
        assert!(store.remove("c1").is_err());
        assert_eq!(store.load().iter().map(|i| i.id.as_str()).collect::<Vec<_>>(), ["c1"]);
        assert!(store.clear().is_err());
        assert_eq!(store.load().len(), 1);
    }

    #[test]
    fn a_copy_already_gone_still_comes_off_the_shelf() {
        let root = temp("gone");
        let store = Store::new(root.clone());
        std::fs::write(root.join("shelf.json"), r#"{"version":1,"items":[{"id":"c1","name":"pic.png","size":3,"copy":true,"addedAt":2}]}"#).unwrap();
        assert!(store.remove("c1").unwrap().is_empty());
        assert!(store.load().is_empty());
    }

    #[test]
    fn a_copy_is_only_ever_one_name_under_its_own_folder() {
        let root = temp("name");
        let store = Store::new(root);
        let item = |name: &str| Item { id: "c1".into(), name: name.into(), size: 0, folder: false, copy: true, link: None, added_at: 0 };
        let inside = store.copies().join("c1");
        assert_eq!(store.path_of(&item("pic.png")), Some(inside.join("pic.png")));
        for name in ["/etc/passwd", "..", "../x", "./x", "a/b", ""] {
            assert_eq!(store.path_of(&item(name)), None, "{name:?}");
        }
        // A drive prefix is two components on Windows (the prefix and the rest), so only Windows refuses these; Linux reads them as one normal name.
        #[cfg(windows)]
        {
            for name in ["C:foo", "C:"] {
                assert_eq!(store.path_of(&item(name)), None, "{name:?}");
            }
        }
    }

    #[test]
    fn a_clear_that_cannot_remove_one_copy_keeps_only_that_item_and_saves_the_rest() {
        let root = temp("clear-partial");
        let store = Store::new(root.clone());
        // c1's copy can go. c2's copy is a plain file at shelf/c2, so removing it fails. c1 is the newer item, so it is handled first.
        let c1 = root.join("shelf").join("c1");
        std::fs::create_dir_all(&c1).unwrap();
        std::fs::write(c1.join("a.png"), b"a").unwrap();
        std::fs::write(root.join("shelf").join("c2"), b"not a folder").unwrap();
        std::fs::write(root.join("shelf.json"), r#"{"version":1,"items":[{"id":"c1","name":"a.png","size":1,"copy":true,"addedAt":2},{"id":"c2","name":"b.png","size":1,"copy":true,"addedAt":1}]}"#).unwrap();
        assert!(store.clear().is_err(), "the failed copy is reported");
        assert!(!c1.exists(), "the first copy is gone");
        assert_eq!(store.load().iter().map(|i| i.id.as_str()).collect::<Vec<_>>(), ["c2"], "the item whose copy stayed is still listed, and the list was saved");
    }

    #[cfg(unix)]
    #[test]
    fn a_shelf_file_that_cannot_be_read_is_not_overwritten() {
        let root = temp("unreadable");
        let store = Store::new(root.clone());
        // shelf.json links to itself: reading it fails with an error other than "not found", so the save must stop before it writes anything.
        std::os::unix::fs::symlink("shelf.json", root.join("shelf.json")).unwrap();
        assert!(store.clear().is_err(), "the save reports the read error");
        assert!(std::fs::symlink_metadata(root.join("shelf.json")).unwrap().file_type().is_symlink(), "the file is untouched");
        assert!(!root.join("shelf.json.tmp").exists(), "nothing was written");
        assert!(std::fs::read_dir(&root).unwrap().flatten().all(|e| !e.file_name().to_string_lossy().starts_with("shelf.json.bad-")), "no backup either");
    }

    #[test]
    fn a_top_level_array_in_shelf_json_is_backed_up_before_it_is_overwritten() {
        let root = temp("array");
        let store = Store::new(root.clone());
        let array = br#"[{"id":"a","name":"a.txt","link":"/a.txt","addedAt":1}]"#;
        std::fs::write(root.join("shelf.json"), array).unwrap();
        store.clear().unwrap();
        let backups: Vec<PathBuf> = std::fs::read_dir(&root)
            .unwrap()
            .flatten()
            .map(|e| e.path())
            .filter(|p| p.file_name().unwrap().to_string_lossy().starts_with("shelf.json.bad-"))
            .collect();
        assert_eq!(backups.len(), 1, "the unreadable top-level array is kept");
        assert_eq!(std::fs::read(&backups[0]).unwrap(), array);
        let new: Value = serde_json::from_slice(&std::fs::read(root.join("shelf.json")).unwrap()).unwrap();
        assert_eq!(new, serde_json::json!({ "version": 1, "items": [] }), "the new shelf.json is a valid, empty shelf");
    }

    #[test]
    fn a_shelf_file_whose_items_is_not_a_list_is_backed_up_before_it_is_overwritten() {
        let root = temp("items-not-list");
        let store = Store::new(root.clone());
        let bytes = br#"{"items":5}"#;
        std::fs::write(root.join("shelf.json"), bytes).unwrap();
        store.clear().unwrap();
        let backups: Vec<PathBuf> = std::fs::read_dir(&root)
            .unwrap()
            .flatten()
            .map(|e| e.path())
            .filter(|p| p.file_name().unwrap().to_string_lossy().starts_with("shelf.json.bad-"))
            .collect();
        assert_eq!(backups.len(), 1, "the file whose items is not a list is kept");
        assert_eq!(std::fs::read(&backups[0]).unwrap(), bytes);
        let new: Value = serde_json::from_slice(&std::fs::read(root.join("shelf.json")).unwrap()).unwrap();
        assert_eq!(new, serde_json::json!({ "version": 1, "items": [] }), "the new shelf.json is a valid, empty shelf");
    }

    #[test]
    fn a_failed_shelf_add_says_a_fixed_reason_and_names_no_path_or_file() {
        // The data folder is a file, so the save cannot write the shelf: the add fails inside Rust, after the dropped file was looked at.
        let root = temp("blocked");
        let blocker = root.join("not-a-folder");
        std::fs::write(&blocker, b"x").unwrap();
        let data = temp("secret-files");
        let file = data.join("secret-plan-2026.txt");
        std::fs::write(&file, b"hello").unwrap();
        let path = file.to_string_lossy().to_string();
        let Err(err) = Store::new(blocker).add_paths(&[path.clone()]).map_err(|e| e.to_string()) else {
            panic!("a save into a file cannot succeed");
        };
        assert_eq!(err, "shelf add failed", "the error is a fixed reason, not the OS text");
        assert!(!err.contains("secret-plan-2026"), "no file name");
        assert!(!err.contains(&path), "no path");
    }
}
