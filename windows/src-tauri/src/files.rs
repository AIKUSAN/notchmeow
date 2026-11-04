// Dropped files are copied into %LOCALAPPDATA%\NotchMeow\inbox so the original is
// never touched and the copy survives the drag source going away.
// The inbox is swept of anything older than a week, as on macOS.

use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};

use serde::Serialize;

use crate::ai::attachments::{self, Classified, RejectReason};
use crate::ai::catalog;
use crate::settings;

const KEEP_FOR: Duration = Duration::from_secs(7 * 24 * 60 * 60);
/// The first eight bytes of every PNG file.
const PNG_SIGNATURE: &[u8] = b"\x89PNG\r\n\x1a\n";
/// What a pasted picture that could not be copied says, and all it says.
const PICTURE_COPY_FAILED: &str = "The picture could not be copied.";

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct DroppedFile {
    pub name: String,
    pub path: String,
    pub size: u64,
}

pub fn inbox_dir() -> PathBuf {
    settings::local_dir().join("inbox")
}

pub fn ingest(source: &str) -> Result<DroppedFile, String> {
    ingest_in(&settings::local_dir(), source)
}

/// `ingest` with the app's data folder given: the copy goes to `root/inbox`.
/// The tests pass a scratch folder, so they never touch the real inbox.
fn ingest_in(root: &Path, source: &str) -> Result<DroppedFile, String> {
    let src = Path::new(source);
    let meta = std::fs::metadata(src).map_err(|e| format!("cannot read {source}: {e}"))?;
    if meta.is_dir() {
        return Err("Folders can't be dropped yet.".into());
    }
    // The cat refuses archives, apps, videos and anything over 25 MB before
    // anything is copied (spec §3).
    if let Classified::Rejected(reason) = attachments::screen(src).map_err(|e| format!("cannot read {source}: {e}"))? {
        return Err(attachments::reject_message(reason).into());
    }

    let dir = root.join("inbox");
    crate::platform::ensure_private_dir(root).map_err(|e| e.to_string())?;
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;

    let name = src
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| "file".into());

    let dest = free_name(&dir, &name);

    std::fs::copy(src, &dest).map_err(|e| format!("cannot copy: {e}"))?;
    // CopyFileEx carries the source's timestamps across, so a file last edited
    // three years ago would arrive already older than the sweep window and be
    // deleted on the spot. The inbox ages from when *we* copied it.
    if let Ok(file) = std::fs::File::options().write(true).open(&dest) {
        let _ = file.set_modified(SystemTime::now());
    }
    sweep(&dir);

    Ok(DroppedFile {
        name,
        path: dest.to_string_lossy().to_string(),
        size: meta.len(),
    })
}

/// The inbox path for `name`: `name` itself, or `stem (2).ext`, `stem (3).ext`… for the first one not taken. Only when 998 are taken does it return
/// `name`'s own path, which the caller must not overwrite (`create_new` refuses it).
fn free_name(dir: &Path, name: &str) -> PathBuf {
    let dest = dir.join(name);
    if !dest.exists() {
        return dest;
    }
    let path = Path::new(name);
    let stem = path.file_stem().map(|s| s.to_string_lossy().to_string()).unwrap_or_default();
    let ext = path.extension().map(|s| format!(".{}", s.to_string_lossy())).unwrap_or_default();
    (2..1000).map(|i| dir.join(format!("{stem} ({i}){ext}"))).find(|c| !c.exists()).unwrap_or(dest)
}

/// A pasted screenshot, copied into the inbox as `screenshot.png` (`screenshot (2).png`… when taken), like a dropped file. The page sends the picture's
/// bytes only; see `ingest_png_in` for what is refused.
pub fn ingest_png(bytes: &[u8]) -> Result<DroppedFile, String> {
    ingest_png_in(&settings::local_dir(), bytes)
}

/// `ingest_png` with the app's data folder given. Only a PNG (its signature) up to the drop's size cap is written; anything else is refused with
/// nothing copied, and the bytes are never logged or named.
fn ingest_png_in(root: &Path, bytes: &[u8]) -> Result<DroppedFile, String> {
    if !bytes.starts_with(PNG_SIGNATURE) {
        return Err("That isn't a picture NotchMeow can read.".into());
    }
    if bytes.len() as u64 > catalog::MAX_FILE_BYTES {
        return Err(attachments::reject_message(RejectReason::Size).into());
    }
    let dir = root.join("inbox");
    // The OS's own words and the path stay out of the error: the page shows what comes back, and a picture's copy is not the person's to read here.
    crate::platform::ensure_private_dir(root).map_err(|_| PICTURE_COPY_FAILED.to_string())?;
    std::fs::create_dir_all(&dir).map_err(|_| PICTURE_COPY_FAILED.to_string())?;
    let dest = free_name(&dir, "screenshot.png");
    // `create_new`: a name taken meanwhile is an error, never an overwrite.
    let mut file = std::fs::File::options().write(true).create_new(true).open(&dest).map_err(|_| PICTURE_COPY_FAILED.to_string())?;
    if file.write_all(bytes).is_err() {
        // A part-written picture is removed, so the inbox never keeps half of one.
        drop(file);
        let _ = std::fs::remove_file(&dest);
        return Err(PICTURE_COPY_FAILED.into());
    }
    sweep(&dir);
    Ok(DroppedFile {
        name: dest.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default(),
        path: dest.to_string_lossy().to_string(),
        size: bytes.len() as u64,
    })
}

/// Drops anything copied here more than a week ago. `ingest` stamps every copy
/// with the time it landed, so this really is the age of the copy and not the
/// age of whatever the user happened to drag in.
fn sweep(dir: &Path) {
    let Ok(entries) = std::fs::read_dir(dir) else { return };
    let now = SystemTime::now();
    for entry in entries.flatten() {
        let Ok(meta) = entry.metadata() else { continue };
        let Ok(copied) = meta.modified() else { continue };
        if now.duration_since(copied).map(|age| age > KEEP_FOR).unwrap_or(false) {
            let _ = std::fs::remove_file(entry.path());
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::UNIX_EPOCH;

    /// A folder of this test's own under the temp dir, created fresh. The name
    /// carries the process id, a per-process counter and the time, so no two
    /// tests or runs share one.
    fn scratch(name: &str) -> PathBuf {
        static COUNTER: AtomicU64 = AtomicU64::new(0);
        let nanos = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_nanos()).unwrap_or(0);
        let n = COUNTER.fetch_add(1, Ordering::Relaxed);
        let dir = std::env::temp_dir().join(format!("notchmeow-{name}-{}-{n}-{nanos}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn ingest_copies_and_never_overwrites() {
        let tmp = scratch("ingest");
        let root = tmp.join("app");
        let source = tmp.join("note.txt");
        std::fs::write(&source, b"hello").unwrap();

        let first = ingest_in(&root, source.to_str().unwrap()).unwrap();
        assert_eq!(first.name, "note.txt");
        assert_eq!(std::fs::read(&first.path).unwrap(), b"hello");

        // A second drop of the same name must not clobber the first copy.
        std::fs::write(&source, b"second").unwrap();
        let second = ingest_in(&root, source.to_str().unwrap()).unwrap();
        assert_ne!(first.path, second.path);
        assert_eq!(std::fs::read(&first.path).unwrap(), b"hello");
        assert_eq!(std::fs::read(&second.path).unwrap(), b"second");

        // Folders are refused rather than silently ignored.
        assert!(ingest_in(&root, tmp.to_str().unwrap()).is_err());

        // An ancient source must not arrive already older than the sweep window.
        let old_source = tmp.join("ancient.txt");
        std::fs::write(&old_source, b"old").unwrap();
        let long_ago = SystemTime::now() - KEEP_FOR - Duration::from_secs(60 * 60);
        std::fs::File::options()
            .write(true)
            .open(&old_source)
            .unwrap()
            .set_modified(long_ago)
            .unwrap();
        let aged = ingest_in(&root, old_source.to_str().unwrap()).unwrap();
        assert!(
            Path::new(&aged.path).exists(),
            "a file copied just now was swept as if it were a week old"
        );
        let _ = std::fs::remove_file(&aged.path);

        let _ = std::fs::remove_file(&first.path);
        let _ = std::fs::remove_file(&second.path);
        let _ = std::fs::remove_dir_all(&tmp);
    }

    /// A PNG's first eight bytes and a little more, as a screenshot's bytes come from the clipboard.
    fn png(len: usize) -> Vec<u8> {
        let mut bytes = b"\x89PNG\r\n\x1a\n".to_vec();
        bytes.resize(len, 7);
        bytes
    }

    #[test]
    fn a_png_is_written_to_the_inbox_with_a_free_name() {
        let tmp = scratch("png");
        let root = tmp.join("app");
        let first = ingest_png_in(&root, &png(64)).unwrap();
        assert_eq!(first.name, "screenshot.png");
        assert_eq!(first.size, 64);
        assert_eq!(std::fs::read(&first.path).unwrap(), png(64));
        assert!(Path::new(&first.path).starts_with(root.join("inbox")));
        // A second paste never overwrites the first, and the name follows the drop's naming.
        let second = ingest_png_in(&root, &png(80)).unwrap();
        assert_eq!(second.name, "screenshot (2).png");
        assert_eq!(std::fs::read(&first.path).unwrap(), png(64), "the first picture is kept");
        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn not_a_png_is_refused_and_nothing_is_written() {
        let tmp = scratch("png-no");
        let root = tmp.join("app");
        let gif = b"GIF89a\x01\x00".to_vec();
        assert_eq!(ingest_png_in(&root, &gif).err().as_deref(), Some("That isn't a picture NotchMeow can read."));
        assert_eq!(ingest_png_in(&root, b"").err().as_deref(), Some("That isn't a picture NotchMeow can read."));
        assert!(!root.join("inbox").exists() || std::fs::read_dir(root.join("inbox")).unwrap().next().is_none(), "nothing was copied");
        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn a_png_over_the_cap_is_refused_and_nothing_is_written() {
        let tmp = scratch("png-big");
        let root = tmp.join("app");
        let too_big = png(catalog::MAX_FILE_BYTES as usize + 1);
        assert_eq!(ingest_png_in(&root, &too_big).err().as_deref(), Some("Files over 25 MB are too big for me."));
        assert!(!root.join("inbox").exists() || std::fs::read_dir(root.join("inbox")).unwrap().next().is_none(), "nothing was copied");
        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn a_picture_that_cannot_be_copied_says_only_the_fixed_sentence() {
        let tmp = scratch("png-fail");
        // The app's folder is a file, so nothing can be made in it; the error must not carry the OS's words or the path.
        let root = tmp.join("app");
        std::fs::write(&root, b"a file, not a folder").unwrap();
        let err = ingest_png_in(&root, &png(64)).err().unwrap();
        assert_eq!(err, PICTURE_COPY_FAILED);
        let path = root.to_string_lossy();
        assert!(!err.contains(path.as_ref()) && !err.contains("os error") && !err.contains("No such") && !err.contains("exists"), "{err}");
        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn the_eight_byte_signature_alone_is_a_picture_and_seven_bytes_are_not() {
        let tmp = scratch("png-sig");
        let root = tmp.join("app");
        let only_signature = ingest_png_in(&root, PNG_SIGNATURE).unwrap();
        assert_eq!(only_signature.size, 8);
        assert_eq!(std::fs::read(&only_signature.path).unwrap(), PNG_SIGNATURE);
        assert_eq!(ingest_png_in(&root, &PNG_SIGNATURE[..7]).err().as_deref(), Some("That isn't a picture NotchMeow can read."));
        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn a_picture_of_exactly_the_cap_is_written_and_one_byte_more_is_not() {
        let tmp = scratch("png-edge");
        let root = tmp.join("app");
        let at_cap = ingest_png_in(&root, &png(catalog::MAX_FILE_BYTES as usize)).unwrap();
        assert_eq!(at_cap.size, catalog::MAX_FILE_BYTES);
        assert_eq!(ingest_png_in(&root, &png(catalog::MAX_FILE_BYTES as usize + 1)).err().as_deref(), Some("Files over 25 MB are too big for me."));
        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn ingest_refuses_what_the_cat_cannot_read() {
        let tmp = scratch("reject");
        let root = tmp.join("app");
        let (zip_name, big_name) = ("nm-test-bundle.zip", "nm-test-huge.txt");

        let zip = tmp.join(zip_name);
        std::fs::write(&zip, b"PK\x03\x04").unwrap();
        assert_eq!(ingest_in(&root, zip.to_str().unwrap()).err().as_deref(), Some("I can't read this kind of file."));
        let big = tmp.join(big_name);
        std::fs::File::create(&big).unwrap().set_len(26_214_401).unwrap();
        assert_eq!(ingest_in(&root, big.to_str().unwrap()).err().as_deref(), Some("Files over 25 MB are too big for me."));
        assert!(!root.join("inbox").join(zip_name).exists() && !root.join("inbox").join(big_name).exists(), "nothing was copied");
        let _ = std::fs::remove_dir_all(&tmp);
    }
}
