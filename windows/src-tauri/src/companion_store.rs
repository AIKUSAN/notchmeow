// The companion's conversation files (sub-project F3a-tauri, docs/COMPANION-CONTRACT.md "Conversation records"): one `<id>.json` per conversation in
// `companion/conversations/` under the app's data folder. The page cleans every record with `conversationClean` (src/companion/core.ts) before it saves it, and keeps at most
// 50 (`conversationsKeep`). Rust checks only what a file needs to be safe: the id, the size, that a link is never followed or replaced, and that a file is written
// owner-only and atomically. Nothing here logs or returns a message, a path or OS text: a refusal is one of two fixed sentences.
//
// Nothing runs unless the person acts (a save after a reply, a delete, a list when the chat opens): no timer, no watcher, no poll.

use std::fs;
use std::io::{ErrorKind, Read, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use serde::Serialize;
use serde_json::Value;

use crate::platform;
use crate::settings;

/// The largest conversation file read or written. A file over it reads as absent and is never overwritten.
pub const FILE_MAX_BYTES: u64 = 8 * 1024 * 1024;
const ID_MAX: usize = 64;
/// The largest whole number a JavaScript number holds exactly (`Number.isSafeInteger`): 2^53 - 1.
const NUMBER_MAX: f64 = 9_007_199_254_740_991.0;
/// What a refused save says, and all it says: no path, no name, no OS text.
pub const SAVE_FAILED: &str = "The conversation could not be saved.";
/// What a refused delete says, and all it says.
pub const DELETE_FAILED: &str = "The conversation could not be deleted.";
/// Temporary names are unique within the process; a name already taken is skipped.
static COUNTER: AtomicU64 = AtomicU64::new(0);

/// The contract's conversation id: `^[a-z0-9][a-z0-9-]{0,63}$`, ASCII only.
pub fn is_id(s: &str) -> bool {
    let b = s.as_bytes();
    (1..=ID_MAX).contains(&b.len()) && (b[0].is_ascii_lowercase() || b[0].is_ascii_digit()) && b.iter().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || *c == b'-')
}

/// The conversations' folder's parent: the app's local data folder on both platforms (where the inbox and the log are). settings.json stays in the
/// preferences folder; the conversations never go there.
pub fn companion_dir() -> PathBuf {
    settings::local_dir().join("companion")
}

/// A temporary name for one save of `id`: the process id, the time and a counter, so no earlier run's orphan (or another save's name) is ever the same.
fn temp_name(id: &str) -> String {
    let n = COUNTER.fetch_add(1, Ordering::Relaxed);
    let nanos = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.subsec_nanos()).unwrap_or(0);
    format!(".{id}.{}-{nanos}-{n}.tmp", std::process::id())
}

/// A file Delete all may remove: a conversation's `<id>.json`, or a leftover temporary file (`.*.tmp`). Nothing else in the folder is named this way.
fn is_sweepable(name: &str) -> bool {
    let conversation = name.strip_suffix(".json").is_some_and(is_id);
    conversation || (name.len() > ".tmp".len() && name.starts_with('.') && name.ends_with(".tmp"))
}

/// One conversation as the chat list shows it. The page takes the rest of the record from `load`.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Head {
    pub id: String,
    pub title: String,
    pub pinned: bool,
    pub updated_at: f64,
}

/// A time in the record: a safe whole number of 0 or more, else 0 (the contract's time rule).
fn whole_time(v: Option<&Value>) -> f64 {
    match v.and_then(Value::as_f64) {
        Some(f) if f.fract() == 0.0 && f >= 0.0 && f <= NUMBER_MAX => f,
        _ => 0.0,
    }
}

/// The head of a record whose `id` is the file's name, or None.
fn head_of(id: &str, rec: &Value) -> Option<Head> {
    let o = rec.as_object()?;
    if o.get("id")?.as_str()? != id {
        return None;
    }
    Some(Head {
        id: id.to_string(),
        title: o.get("title").and_then(Value::as_str).unwrap_or("").to_string(),
        pinned: o.get("pinned") == Some(&Value::Bool(true)),
        updated_at: whole_time(o.get("updatedAt")),
    })
}

/// The file's metadata when `path` is a regular file (`symlink_metadata` does not follow a link) and not larger than `max`.
fn plain_file(path: &Path, max: u64) -> Option<fs::Metadata> {
    let meta = fs::symlink_metadata(path).ok()?;
    (meta.file_type().is_file() && meta.len() <= max).then_some(meta)
}

/// The conversation folder. `root` holds `<id>.json` files and nothing else is read or changed in it.
pub struct Store {
    root: PathBuf,
}

impl Store {
    pub fn new(root: PathBuf) -> Store {
        Store { root }
    }

    fn path_of(&self, id: &str) -> PathBuf {
        self.root.join(format!("{id}.json"))
    }

    /// The parsed record at `id`'s file, or None: a missing file, a link, another kind of file, one over the size, text that is not a JSON object, or one whose `id`
    /// is not its file name.
    fn read_record(&self, id: &str) -> Option<Value> {
        if !is_id(id) {
            return None;
        }
        let path = self.path_of(id);
        plain_file(&path, FILE_MAX_BYTES)?;
        // On Linux the open itself refuses a link planted after the check above (`O_NOFOLLOW`, as link/files.rs does).
        let mut options = fs::OpenOptions::new();
        options.read(true);
        #[cfg(target_os = "linux")]
        std::os::unix::fs::OpenOptionsExt::custom_flags(&mut options, libc::O_NOFOLLOW);
        let mut bytes = Vec::new();
        options.open(&path).ok()?.take(FILE_MAX_BYTES + 1).read_to_end(&mut bytes).ok()?;
        if bytes.len() as u64 > FILE_MAX_BYTES {
            return None;
        }
        let rec: Value = serde_json::from_slice(&bytes).ok()?;
        (rec.get("id").and_then(Value::as_str) == Some(id)).then_some(rec)
    }

    /// Every conversation file that reads, as a head, sorted by id. Anything else in the folder is skipped.
    pub fn list(&self) -> Vec<Head> {
        let Ok(entries) = fs::read_dir(&self.root) else { return Vec::new() };
        let mut heads: Vec<Head> = entries
            .flatten()
            .filter_map(|e| {
                let name = e.file_name().into_string().ok()?;
                let id = name.strip_suffix(".json")?;
                head_of(id, &self.read_record(id)?)
            })
            .collect();
        heads.sort_by(|a, b| a.id.cmp(&b.id));
        heads
    }

    /// One record as it was saved, or None (see `read_record`).
    pub fn load(&self, id: &str) -> Option<Value> {
        self.read_record(id)
    }

    /// Writes `record` as `<its id>.json`: owner-only, atomically (a temporary file, then a rename over the old file). Refused, with the fixed sentence, when the id is
    /// not the contract's, the text is over the size, or a link or an over-size file is at the path.
    pub fn save(&self, record: &Value) -> Result<(), &'static str> {
        let id = record.get("id").and_then(Value::as_str).filter(|id| is_id(id)).ok_or(SAVE_FAILED)?;
        let body = serde_json::to_vec(record).map_err(|_| SAVE_FAILED)?;
        if body.len() as u64 > FILE_MAX_BYTES {
            return Err(SAVE_FAILED);
        }
        let path = self.path_of(id);
        match fs::symlink_metadata(&path) {
            Ok(meta) if !meta.file_type().is_file() || meta.len() > FILE_MAX_BYTES => return Err(SAVE_FAILED),
            Ok(_) => {}
            Err(e) if e.kind() == ErrorKind::NotFound => {}
            Err(_) => return Err(SAVE_FAILED),
        }
        platform::ensure_private_dir(&self.root).map_err(|_| SAVE_FAILED)?;
        let tmp = self.new_temp(id, &body).map_err(|_| SAVE_FAILED)?;
        let renamed = fs::rename(&tmp, &path);
        if renamed.is_err() {
            let _ = fs::remove_file(&tmp);
        }
        renamed.map_err(|_| SAVE_FAILED)
    }

    /// A new temporary file for `id`, created exclusively (`create_new`, so a link planted at the name is never followed), owner-only on unix, written and synced.
    /// Its name starts with a dot, so `list` never reads it. A name already taken is skipped, a few times at most.
    fn new_temp(&self, id: &str, body: &[u8]) -> std::io::Result<PathBuf> {
        let mut taken = None;
        for _ in 0..8 {
            let tmp = self.root.join(temp_name(id));
            let mut options = fs::OpenOptions::new();
            options.write(true).create_new(true);
            #[cfg(unix)]
            std::os::unix::fs::OpenOptionsExt::mode(&mut options, 0o600);
            match options.open(&tmp) {
                Ok(mut file) => {
                    let written = file.write_all(body).and_then(|_| file.sync_all());
                    if written.is_err() {
                        drop(file);
                        let _ = fs::remove_file(&tmp);
                    }
                    return written.map(|_| tmp);
                }
                Err(e) if e.kind() == ErrorKind::AlreadyExists => taken = Some(e),
                Err(e) => return Err(e),
            }
        }
        Err(taken.unwrap_or_else(|| std::io::Error::other("no free temporary name")))
    }

    /// Removes `<id>.json` when it is a regular file. A missing file is fine; a link or another kind is left alone (never followed or removed) and is not an error.
    pub fn delete(&self, id: &str) -> Result<(), &'static str> {
        if !is_id(id) {
            return Err(DELETE_FAILED);
        }
        let path = self.path_of(id);
        match fs::symlink_metadata(&path) {
            Ok(meta) if meta.file_type().is_file() => fs::remove_file(&path).map_err(|_| DELETE_FAILED),
            Ok(_) => Ok(()),
            Err(e) if e.kind() == ErrorKind::NotFound => Ok(()),
            Err(_) => Err(DELETE_FAILED),
        }
    }

    /// Removes every regular `<id>.json` in the folder and returns how many. Nothing else is touched; a missing folder holds nothing.
    pub fn delete_all(&self) -> Result<usize, &'static str> {
        let (removed, outcome) = self.delete_all_counting();
        outcome.map(|()| removed)
    }

    /// The same delete, reporting what it did even when it stopped early: how many files went (they stay gone), and the fixed sentence when it stopped.
    /// It also sweeps the leftover temporary files (`.*.tmp`) of saves that stopped part way. Those count in the number, as a file that went: the open chat
    /// forgets its id when any file went (`announces`), and a leftover is never the chat's to keep. A link or a folder is never followed or removed.
    pub fn delete_all_counting(&self) -> (usize, Result<(), &'static str>) {
        self.delete_all_with(|path| fs::remove_file(path))
    }

    /// `delete_all_counting` with the removal given, so a test can make one fail part way.
    fn delete_all_with(&self, remove: impl Fn(&Path) -> std::io::Result<()>) -> (usize, Result<(), &'static str>) {
        let entries = match fs::read_dir(&self.root) {
            Ok(entries) => entries,
            Err(e) if e.kind() == ErrorKind::NotFound => return (0, Ok(())),
            Err(_) => return (0, Err(DELETE_FAILED)),
        };
        let mut removed = 0;
        for entry in entries {
            let Ok(entry) = entry else { return (removed, Err(DELETE_FAILED)) };
            let name = entry.file_name();
            if !name.to_str().is_some_and(is_sweepable) {
                continue;
            }
            let path = entry.path();
            if !fs::symlink_metadata(&path).is_ok_and(|m| m.file_type().is_file()) {
                continue;
            }
            if remove(&path).is_err() {
                return (removed, Err(DELETE_FAILED));
            }
            removed += 1;
        }
        (removed, Ok(()))
    }
}

/// Whether a Delete all that removed `removed` files changed the saved conversations: when one went, the open chat must forget its id even if the rest
/// failed (a file already gone is not written back). A delete that removed nothing changes nothing, so the open chat stays.
pub fn announces(removed: usize) -> bool {
    removed > 0
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn temp(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("notchmeow-companion-{tag}-{}-{}", std::process::id(), COUNTER.fetch_add(1, Ordering::Relaxed)));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn record(id: &str, title: &str) -> Value {
        json!({ "version": 1, "id": id, "title": title, "pinned": false, "createdAt": 1, "updatedAt": 2, "messages": [] })
    }

    fn head(id: &str, title: &str, pinned: bool, updated_at: f64) -> Head {
        Head { id: id.into(), title: title.into(), pinned, updated_at }
    }

    #[test]
    fn a_saved_record_lists_and_loads_back() {
        let store = Store::new(temp("roundtrip"));
        let rec = record("c1", "Hello");
        store.save(&rec).unwrap();
        assert_eq!(store.list(), vec![head("c1", "Hello", false, 2.0)]);
        assert_eq!(store.load("c1"), Some(rec));
        assert_eq!(store.load("nope"), None);
        assert_eq!(serde_json::to_value(&store.list()[0]).unwrap()["updatedAt"], 2.0);
    }

    #[test]
    fn a_bad_id_is_refused() {
        let store = Store::new(temp("badid"));
        let long = "a".repeat(65);
        for id in ["../x", "A", "", "-x", "a/b", long.as_str()] {
            assert_eq!(store.save(&record(id, "t")), Err(SAVE_FAILED), "{id:?}");
            assert_eq!(store.load(id), None, "{id:?}");
        }
        assert_eq!(store.save(&json!({ "title": "no id" })), Err(SAVE_FAILED));
        assert_eq!(store.save(&record(&"b".repeat(64), "edge")), Ok(()), "64 characters is the longest id");
        assert_eq!(store.list().len(), 1);
    }

    #[cfg(unix)]
    #[test]
    fn a_symlink_is_not_followed_and_not_replaced() {
        let root = temp("link");
        let outside = temp("outside").join("secret.txt");
        fs::write(&outside, b"keep me").unwrap();
        std::os::unix::fs::symlink(&outside, root.join("c1.json")).unwrap();
        let store = Store::new(root.clone());
        assert!(store.list().is_empty(), "a link is not listed");
        assert_eq!(store.load("c1"), None);
        assert_eq!(store.save(&record("c1", "x")), Err(SAVE_FAILED));
        assert_eq!(store.delete("c1"), Ok(()));
        assert_eq!(fs::read(&outside).unwrap(), b"keep me", "the target is never written or removed");
        assert!(fs::symlink_metadata(root.join("c1.json")).unwrap().file_type().is_symlink(), "the link stays");
    }

    #[test]
    fn a_file_over_8_mib_is_skipped_and_kept() {
        let root = temp("big");
        let big = root.join("big.json");
        let text = format!(r#"{{"id":"big","title":"t","messages":["{}"]}}"#, "x".repeat(FILE_MAX_BYTES as usize));
        fs::write(&big, &text).unwrap();
        let store = Store::new(root.clone());
        assert!(store.list().is_empty());
        assert_eq!(store.load("big"), None);
        assert_eq!(store.save(&json!({ "id": "big", "title": "small" })), Err(SAVE_FAILED), "an over-size file is never overwritten");
        assert_eq!(fs::read(&big).unwrap(), text.as_bytes());
        let huge = json!({ "id": "huge", "title": "x".repeat(FILE_MAX_BYTES as usize) });
        assert_eq!(store.save(&huge), Err(SAVE_FAILED), "a record over the size is refused");
        assert!(fs::metadata(root.join("huge.json")).is_err(), "and nothing is written");
    }

    #[test]
    fn junk_json_and_a_mismatched_id_are_skipped() {
        let root = temp("junk");
        fs::write(root.join("junk.json"), b"{not json").unwrap();
        fs::write(root.join("array.json"), b"[1,2]").unwrap();
        fs::write(root.join("other.json"), br#"{"id":"else","title":"x"}"#).unwrap();
        fs::write(root.join("Bad.json"), br#"{"id":"Bad"}"#).unwrap();
        fs::write(root.join("notes.json.txt"), br#"{"id":"notes"}"#).unwrap();
        fs::write(root.join("good.json"), br#"{"id":"good","title":"ok","pinned":true,"updatedAt":5}"#).unwrap();
        let store = Store::new(root);
        assert_eq!(store.list(), vec![head("good", "ok", true, 5.0)]);
        assert_eq!(store.load("other"), None, "its id is not its file name");
        assert_eq!(store.load("junk"), None);
    }

    #[test]
    fn a_time_that_is_not_a_safe_whole_number_is_zero() {
        let root = temp("time");
        let store = Store::new(root.clone());
        for (raw, want) in [("42", 42.0), ("10.5", 0.0), ("-3", 0.0), ("1e300", 0.0), ("9007199254740992", 0.0), ("9007199254740991", 9007199254740991.0)] {
            fs::write(root.join("t.json"), format!(r#"{{"id":"t","updatedAt":{raw}}}"#)).unwrap();
            assert_eq!(store.list()[0].updated_at, want, "{raw}");
        }
        fs::write(root.join("t.json"), br#"{"id":"t"}"#).unwrap();
        assert_eq!(store.list()[0].updated_at, 0.0, "no time at all");
    }

    #[test]
    fn delete_all_removes_only_conversation_files() {
        let root = temp("delete-all");
        let store = Store::new(root.clone());
        store.save(&record("c1", "a")).unwrap();
        store.save(&record("c2", "b")).unwrap();
        fs::write(root.join("notes.txt"), b"mine").unwrap();
        fs::write(root.join("Bad.json"), b"{}").unwrap();
        fs::create_dir_all(root.join("sub")).unwrap();
        fs::write(root.join("sub").join("c3.json"), b"{}").unwrap();
        assert_eq!(store.delete_all(), Ok(2));
        assert!(store.list().is_empty());
        assert!(root.join("notes.txt").exists());
        assert!(root.join("Bad.json").exists());
        assert!(root.join("sub").join("c3.json").exists());
        assert_eq!(Store::new(temp("none").join("missing")).delete_all(), Ok(0), "no folder, nothing to delete");
    }

    #[test]
    fn delete_all_counting_reports_the_removed_files_with_an_ok_outcome() {
        let root = temp("delete-all-counting");
        let store = Store::new(root.clone());
        store.save(&record("c1", "a")).unwrap();
        store.save(&record("c2", "b")).unwrap();
        assert_eq!(store.delete_all_counting(), (2, Ok(())));
        assert_eq!(Store::new(temp("counting-none").join("missing")).delete_all_counting(), (0, Ok(())));
    }

    #[test]
    fn announces_only_when_a_file_went() {
        assert!(!announces(0), "a failed delete that removed nothing must not empty the open chat");
        assert!(announces(1), "a file that went announces, even when the rest failed");
    }

    #[test]
    fn a_delete_removes_one_file_and_a_missing_one_is_fine() {
        let store = Store::new(temp("delete-one"));
        store.save(&record("c1", "a")).unwrap();
        assert_eq!(store.delete("c1"), Ok(()));
        assert!(store.list().is_empty());
        assert_eq!(store.load("c1"), None);
        assert_eq!(store.delete("c1"), Ok(()), "a missing file is fine");
        assert_eq!(store.delete("../x"), Err(DELETE_FAILED));
    }

    #[cfg(unix)]
    #[test]
    fn the_file_is_owner_only() {
        use std::os::unix::fs::PermissionsExt;
        let root = temp("mode");
        let store = Store::new(root.clone());
        store.save(&record("c1", "a")).unwrap();
        store.save(&record("c1", "b")).unwrap();
        assert_eq!(fs::metadata(root.join("c1.json")).unwrap().permissions().mode() & 0o777, 0o600);
        assert_eq!(fs::metadata(&root).unwrap().permissions().mode() & 0o077, 0, "the folder is closed to others");
    }

    #[test]
    fn no_temp_file_is_left_after_a_save() {
        let root = temp("temp");
        let store = Store::new(root.clone());
        store.save(&record("c1", "a")).unwrap();
        let names: Vec<String> = fs::read_dir(&root).unwrap().map(|e| e.unwrap().file_name().to_string_lossy().to_string()).collect();
        assert_eq!(names, vec!["c1.json".to_string()]);
    }

    #[test]
    fn the_conversations_live_in_the_local_data_folder_on_every_platform() {
        assert_eq!(companion_dir(), settings::local_dir().join("companion"));
    }

    #[test]
    fn an_orphan_temp_file_is_swept_with_the_conversations() {
        let root = temp("orphan");
        let store = Store::new(root.clone());
        store.save(&record("c1", "a")).unwrap();
        // The leftover of a save that stopped between its write and its rename.
        fs::write(root.join(".c1.1-2-3.tmp"), b"half a record").unwrap();
        assert_eq!(store.delete_all_counting(), (2, Ok(())), "the orphan counts as a file that went");
        assert!(fs::read_dir(&root).unwrap().next().is_none(), "nothing is left in the folder");
    }

    #[test]
    fn a_save_is_not_blocked_by_orphans_in_the_folder() {
        let root = temp("orphans-block");
        let store = Store::new(root.clone());
        // Eight orphans is the most one save tries; a new save still finds a free temporary name.
        for i in 0..8 {
            fs::write(root.join(format!(".c1.{i}.tmp")), b"x").unwrap();
        }
        assert_eq!(store.save(&record("c1", "a")), Ok(()));
        assert_eq!(store.load("c1").map(|r| r["title"].clone()), Some(json!("a")));
    }

    #[test]
    fn temporary_names_are_not_repeated() {
        assert_ne!(temp_name("c1"), temp_name("c1"));
    }

    #[cfg(unix)]
    #[test]
    fn delete_all_leaves_a_link_and_its_target_alone() {
        let root = temp("delete-all-link");
        let outside = temp("delete-all-outside").join("secret.txt");
        fs::write(&outside, b"keep me").unwrap();
        std::os::unix::fs::symlink(&outside, root.join("c1.json")).unwrap();
        std::os::unix::fs::symlink(&outside, root.join(".c2.1-2-3.tmp")).unwrap();
        let store = Store::new(root.clone());
        assert_eq!(store.delete_all_counting(), (0, Ok(())));
        assert_eq!(fs::read(&outside).unwrap(), b"keep me", "the target is never removed");
        assert!(fs::symlink_metadata(root.join("c1.json")).unwrap().file_type().is_symlink(), "the link stays");
        assert!(fs::symlink_metadata(root.join(".c2.1-2-3.tmp")).unwrap().file_type().is_symlink(), "a linked temp file stays");
    }

    #[test]
    fn delete_all_leaves_a_folder_named_like_a_conversation_alone() {
        let root = temp("delete-all-dir");
        fs::create_dir_all(root.join("c1.json")).unwrap();
        fs::create_dir_all(root.join(".c2.1-2-3.tmp")).unwrap();
        let store = Store::new(root.clone());
        assert_eq!(store.delete_all_counting(), (0, Ok(())));
        assert!(root.join("c1.json").is_dir());
        assert!(root.join(".c2.1-2-3.tmp").is_dir());
    }

    #[cfg(unix)]
    #[test]
    fn a_folder_that_cannot_be_written_removes_nothing_and_says_so() {
        use std::os::unix::fs::PermissionsExt;
        let root = temp("delete-all-ro");
        let store = Store::new(root.clone());
        store.save(&record("c1", "a")).unwrap();
        fs::set_permissions(&root, fs::Permissions::from_mode(0o500)).unwrap();
        // A root user removes files in a folder that is not writable for anyone else; there is then nothing this test can check.
        let privileged = fs::File::create(root.join("probe")).is_ok();
        if privileged {
            fs::remove_file(root.join("probe")).unwrap();
        }
        let result = if privileged { None } else { Some(store.delete_all_counting()) };
        fs::set_permissions(&root, fs::Permissions::from_mode(0o700)).unwrap();
        match result {
            Some(result) => {
                assert_eq!(result, (0, Err(DELETE_FAILED)));
                assert_eq!(store.list().len(), 1, "the conversation is still there");
            }
            None => eprintln!("skipped: this test runs as a user who can write to any folder"),
        }
    }

    #[test]
    fn a_removal_that_fails_part_way_keeps_the_count_of_what_went() {
        let root = temp("delete-all-partial");
        let store = Store::new(root.clone());
        store.save(&record("c1", "a")).unwrap();
        store.save(&record("c2", "b")).unwrap();
        let calls = std::cell::Cell::new(0);
        let result = store.delete_all_with(|path| {
            calls.set(calls.get() + 1);
            if calls.get() == 2 {
                return Err(std::io::Error::other("refused"));
            }
            fs::remove_file(path)
        });
        assert_eq!(result, (1, Err(DELETE_FAILED)), "the one that went is counted, and the failure is the fixed sentence");
        assert_eq!(store.list().len(), 1, "the file that went stays gone and the other is kept");
    }
}
