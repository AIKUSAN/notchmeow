// Dragging files out of the island (sub-project G1; the spike of the Windows/Linux plan's Task 1, then the shelf's drag out).
//
// The page cannot start a drag of real files: Tauri's drag-and-drop setting (which the island needs, to receive files) turns the webview's own drag off. So a press that moves on a
// shelf tile asks Rust for a native drag source: Windows runs OLE's `DoDragDrop` with a shell data object (platform/windows/drag.rs), Linux starts a GTK drag whose data is a
// `text/uri-list` (platform/linux/drag.rs). Both only copy: an original is never moved or deleted by a drag.
//
// THE FALLBACK, one line each. If the owner's real-machine check says a system cannot do it, that system's constant below goes to `false`: the shelf then hides the drag (the tile
// is still ticked by a click) and keeps Ask, Send and Show in folder. Nothing else changes.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use tauri::AppHandle;

use crate::{island, platform};

/// Windows can drag files out of the island (OLE `DoDragDrop`). Set to `false` if the real-machine check fails.
pub const WINDOWS: bool = true;
/// Linux can drag files out of the island (a GTK drag source with `text/uri-list`). Set to `false` if the real-machine check fails on Linux.
pub const LINUX: bool = true;

/// Whether this system's island can drag files out. The shelf shows the drag only where this is true.
pub fn supported() -> bool {
    if cfg!(windows) {
        WINDOWS
    } else {
        LINUX
    }
}

/// A `file://` URI for a path, as a `text/uri-list` holds it: every byte outside `A-Za-z0-9-._~` and the path separator and a drive colon is `%XX` of its UTF-8 byte.
/// Only Windows reads `\` as a separator; elsewhere it is a name character and stays escaped.
#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
pub fn file_uri(path: &Path) -> String {
    let raw = path.to_string_lossy();
    let text = if cfg!(windows) { raw.replace('\\', "/") } else { raw.into_owned() };
    let mut out = String::from("file://");
    if !text.starts_with('/') {
        out.push('/'); // C:/Users/... becomes file:///C:/Users/...
    }
    for (i, b) in text.bytes().enumerate() {
        let drive_colon = b == b':' && i == 1 && text.as_bytes()[0].is_ascii_alphabetic();
        if b.is_ascii_alphanumeric() || matches!(b, b'-' | b'.' | b'_' | b'~' | b'/') || drive_colon {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

/// The arguments of `gdbus` for the freedesktop call that shows a file selected in the user's file manager: `FileManager1.ShowItems(["file://…"], "")`.
#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
pub fn show_items_args(path: &Path) -> Vec<String> {
    // `file_uri` escapes everything but letters, digits and `-._~/`, so the URI holds no quote that could end the list early.
    let list = format!("['{}']", file_uri(path));
    ["call", "--session", "--dest", "org.freedesktop.FileManager1", "--object-path", "/org/freedesktop/FileManager1", "--method", "org.freedesktop.FileManager1.ShowItems"]
        .iter()
        .map(|s| s.to_string())
        .chain([list, String::new()])
        .collect()
}

/// True while a drag-out holds the slot: the native drag takes the main thread, so a second one would fight the first. A drag is refused while one runs. The slot is released when the drag
/// returns, or after the 300 s timeout in `start` gives up on it, and the native drag may still be running then.
static RUNNING: AtomicBool = AtomicBool::new(false);

/// Takes the drag-out slot. False when a drag is already running.
fn claim() -> bool {
    RUNNING.compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire).is_ok()
}

/// Gives the slot back when dropped, so every path out of `start` frees it.
struct Slot;

impl Drop for Slot {
    fn drop(&mut self) {
        RUNNING.store(false, Ordering::Release);
    }
}

/// Drags these files out of the island's window until the user lets go: `copied` when a target took a copy, `none` when it landed where nothing accepts files, `cancelled`
/// for Escape. Runs on the main thread (OLE and GTK both need it) and answers when the drag ends, so the caller can ignore the drop that comes back to the island itself.
pub async fn start(app: &AppHandle, paths: Vec<PathBuf>) -> Result<&'static str, String> {
    if !supported() {
        return Err("Dragging files out is not available on this system.".into());
    }
    if paths.is_empty() {
        return Err("Nothing to drag.".into());
    }
    if !claim() {
        return Err("A drag is already running.".into());
    }
    let _slot = Slot;
    let win = island::window(app).ok_or_else(|| "The island window is not there.".to_string())?;
    let (tx, rx) = tokio::sync::oneshot::channel::<Result<&'static str, String>>();
    let target = win.clone();
    win.run_on_main_thread(move || {
        platform::drag_out(&target, paths, Box::new(move |result| drop(tx.send(result))));
    })
    .map_err(|e| e.to_string())?;
    // A drag that never reports its end (a compositor that lost it) must not hang the page's call for good.
    match tokio::time::timeout(Duration::from_secs(300), rx).await {
        Ok(Ok(result)) => result,
        Ok(Err(_)) => Err("The drag ended without an answer.".into()),
        Err(_) => Err("The drag did not end.".into()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_unix_path_becomes_a_file_uri_with_everything_unusual_escaped() {
        assert_eq!(file_uri(Path::new("/home/me/a b#c%d.txt")), "file:///home/me/a%20b%23c%25d.txt");
        assert_eq!(file_uri(Path::new("/tmp/é😀")), "file:///tmp/%C3%A9%F0%9F%98%80");
        assert_eq!(file_uri(Path::new("/a/b-c_d.e~f")), "file:///a/b-c_d.e~f");
    }

    #[cfg(windows)]
    #[test]
    fn a_windows_path_gets_its_drive_and_forward_slashes() {
        assert_eq!(file_uri(Path::new("C:\\Users\\me\\My Files\\é.txt")), "file:///C:/Users/me/My%20Files/%C3%A9.txt");
        assert_eq!(file_uri(Path::new("c:\\x")), "file:///c:/x");
    }

    #[cfg(not(windows))]
    #[test]
    fn a_backslash_in_a_unix_file_name_is_a_name_character_not_a_separator() {
        // On Linux `\` is part of the file name: it must stay `%5C`, not become `/`, or Show in folder asks the file manager for another file.
        assert_eq!(file_uri(Path::new("/tmp/a\\b.txt")), "file:///tmp/a%5Cb.txt");
    }

    #[test]
    fn a_colon_that_is_not_a_drive_is_escaped() {
        assert_eq!(file_uri(Path::new("/home/me/a:b")), "file:///home/me/a%3Ab");
    }

    #[test]
    fn show_in_folder_asks_the_file_manager_by_gdbus_with_a_uri_list_that_cannot_break_out_of_its_quotes() {
        let args = show_items_args(Path::new("/home/me/it's here/a b.txt"));
        assert_eq!(args[..8], ["call", "--session", "--dest", "org.freedesktop.FileManager1", "--object-path", "/org/freedesktop/FileManager1", "--method", "org.freedesktop.FileManager1.ShowItems"]);
        assert_eq!(args[8], "['file:///home/me/it%27s%20here/a%20b.txt']");
        assert_eq!(args[9], "", "the startup id");
        assert_eq!(args.len(), 10);
    }

    #[test]
    fn a_second_drag_out_is_refused_while_one_runs_and_the_slot_comes_back_when_it_ends() {
        assert!(claim(), "the first drag takes the slot");
        assert!(!claim(), "a second drag is refused while the first runs");
        drop(Slot);
        assert!(claim(), "the slot comes back when the drag ends");
        drop(Slot);
    }

    #[test]
    fn the_fallback_is_the_constant_of_the_system_it_runs_on() {
        // The plan's fallback is a one-line edit of WINDOWS or LINUX; `supported` reads the one for this system.
        assert_eq!(supported(), if cfg!(windows) { WINDOWS } else { LINUX });
    }
}
