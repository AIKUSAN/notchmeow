// Files on the link (sub-project G2): where a received file is written and how, and how a file is read to be sent. The Mac's twin is LinkFiles.swift.
//
// Receiving. The folder is `Downloads/NotchMeow/`. The name is the sanitized one (`name.rs`), made free with `unique_name` and then **created exclusively** (`create_new`: `O_EXCL` on Linux,
// `CREATE_NEW` on Windows): the sanitizer compares names the way the usual volumes do, but the volume decides which names are the same file, so on "already exists" the next free name is
// tried (docs/LINK-CONTRACT.md, known limits). On Linux the file is never followed through a link (`O_NOFOLLOW`), is created private (0600) and made ordinary (0644) only when it is
// complete. The file is never opened by the app. A transfer that does not complete leaves nothing behind (`discard`). On Windows the mark of the web (the `Zone.Identifier` stream, zone 3,
// "the Internet") is written when the file is created, so that even a partial file carries it, as the Mac's quarantine attribute does; a file that cannot be marked is not handed out
// (it is discarded and the transfer fails). Linux has no standard mark.
//
// **A discard never goes by a path on Windows (G2b), except one removal in `open()`:** when Windows refuses the mark for deletion, the file, made a moment before, is removed by its path. The file is created with DELETE access and without `FILE_SHARE_DELETE`, so while this sink holds it nobody else can rename it, replace it or
// delete it, and the name means this file. Once the mark of the web is written (that stream is opened by path, which a file that is already waiting for deletion refuses) the file is marked for
// deletion through the handle (`doom`, `SetFileInformationByHandle`); `finish` takes that mark off, as its last step, and a file whose mark cannot be taken off stays marked and goes when the
// handle closes (the download fails closed). So from `arm` on, `discard`, a dropped sink, a failed `finish`, a crash and `kill -9` all end the same way: the last handle closes and Windows removes the file. The delete-pending state lives in memory only, so a power loss or a blue screen still leaves the partial file.
// Known limit: between `create_exclusive` and `arm` (which includes writing the mark of the web, and that has to come first because a file waiting for deletion refuses the stream open) the file is not
// yet marked for deletion, so a crash or `kill -9` in that short window can leave an unmarked partial file in `Downloads/NotchMeow`.
// The pure rules of that sequence (`arm`, `clear`) are tested on every platform; the two calls that touch Windows (`create_exclusive`'s access and sharing, `doom`) are Windows-only and are
// compiled and run by CI (windows-tests.yml) and by the owner's check. Linux keeps its device and inode check.

use std::fs::{File, OpenOptions};
use std::io::{Read, Write};
use std::path::{Component, Path, PathBuf};
use std::sync::{Mutex, MutexGuard};

use super::frames::{RAW_NAME_MAX, SIZE_MAX};
use super::name::unique_name;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SinkError {
    NoFolder,
    NoFreeName,
    /// Windows: the file could not be marked as downloaded (a drive that has no streams, such as FAT).
    Mark,
    Io,
}

/// Windows writes the mark of the web; Linux has none.
pub const MARK_BY_HAND: bool = cfg!(windows);

/// What `arm` found: the file is ready to be handed out, or the open must fail with `err`. `doomed` says whether the file is marked for deletion (closing the handle removes it) or whether
/// the caller must remove it by its path as a last resort.
#[cfg_attr(not(windows), allow(dead_code))]
#[derive(Debug, PartialEq, Eq)]
pub(crate) enum Armed {
    Ready,
    Failed { err: SinkError, doomed: bool },
}

/// Windows, right after the file was created and the mark of the web written (`marked` is whether that worked): marks the file for deletion through `doom` (`doom(true)`), so that from now on a
/// partial file cannot outlive its handle. The mark is asked for even when the file could not be marked, so that such a file is removed by the handle too.
#[cfg_attr(not(windows), allow(dead_code))]
pub(crate) fn arm(marked: bool, mut doom: impl FnMut(bool) -> bool) -> Armed {
    let doomed = doom(true);
    if !marked {
        return Armed::Failed { err: SinkError::Mark, doomed };
    }
    if !doomed {
        return Armed::Failed { err: SinkError::Io, doomed: false };
    }
    Armed::Ready
}

/// Windows, the transfer is complete: takes the mark for deletion off. A file whose mark cannot be taken off is not kept: the caller closes the handle and Windows removes it.
#[cfg_attr(not(windows), allow(dead_code))]
pub(crate) fn clear(mut doom: impl FnMut(bool) -> bool) -> Result<(), SinkError> {
    if doom(false) {
        Ok(())
    } else {
        Err(SinkError::Io)
    }
}

/// `Downloads/NotchMeow/` of the user.
pub fn default_folder() -> PathBuf {
    downloads_dir().join("NotchMeow")
}

#[cfg(windows)]
fn downloads_dir() -> PathBuf {
    use windows::Win32::System::Com::CoTaskMemFree;
    use windows::Win32::UI::Shell::{FOLDERID_Downloads, SHGetKnownFolderPath, KF_FLAG_DEFAULT};
    // SAFETY: the known-folder call returns a CoTaskMem string that is read once and freed once.
    let known = unsafe {
        SHGetKnownFolderPath(&FOLDERID_Downloads, KF_FLAG_DEFAULT, None).ok().and_then(|p| {
            let s = p.to_string().ok();
            CoTaskMemFree(Some(p.0 as *const _));
            s
        })
    };
    known.map(PathBuf::from).unwrap_or_else(|| crate::platform::home_dir().join("Downloads"))
}

#[cfg(not(windows))]
fn downloads_dir() -> PathBuf {
    let home = crate::platform::home_dir(); // with HOME unset this is "." and `Sink::open` refuses a folder that is not absolute
    let config = std::env::var_os("XDG_CONFIG_HOME").map(PathBuf::from).unwrap_or_else(|| home.join(".config"));
    std::fs::read_to_string(config.join("user-dirs.dirs")).ok().and_then(|t| parse_user_dirs(&t, &home)).unwrap_or_else(|| home.join("Downloads"))
}

/// The XDG download folder from the text of `user-dirs.dirs` (`XDG_DOWNLOAD_DIR="$HOME/Downloads"`), or None when it is not there or does not name a folder under `home`.
#[cfg(not(windows))]
fn parse_user_dirs(text: &str, home: &Path) -> Option<PathBuf> {
    let line = text.lines().map(str::trim).find(|l| l.starts_with("XDG_DOWNLOAD_DIR="))?;
    let value = line.trim_start_matches("XDG_DOWNLOAD_DIR=").trim().trim_matches('"');
    let path = if let Some(rest) = value.strip_prefix("$HOME") { home.join(rest.trim_start_matches('/')) } else { PathBuf::from(value) };
    (path.is_absolute() && path != home).then_some(path)
}

/// The partial files of the receives in progress, for the whole process: `Sink::open` adds one, `finish` and `discard` take it away. A clean quit (`remove_partials`) removes what is left, so
/// that a quit in the middle of a receive leaves no truncated file. On Linux, `kill -9` and a power cut cannot be answered here; on Windows a file already marked for deletion goes when its handle closes at process teardown, whatever the way out.
static PARTIALS: Mutex<Vec<PathBuf>> = Mutex::new(Vec::new());

fn partials() -> MutexGuard<'static, Vec<PathBuf>> {
    PARTIALS.lock().unwrap_or_else(|e| e.into_inner())
}

/// Removes the partial file of every receive in progress (the app is quitting). Unix: plain `remove_file`, a quit has no time for more. Windows: it only unlists them; the handles close at process teardown and Windows removes the files.
pub fn remove_partials() {
    remove_partials_matching(|_| true);
}

fn unlist(path: &Path) {
    partials().retain(|p| p != path);
}

fn remove_partials_matching(wanted: impl Fn(&Path) -> bool) {
    partials().retain(|p| {
        if !wanted(p) {
            return true;
        }
        // Windows: the sink's handle is marked for deletion and nobody else may delete the file, so the file goes when the process ends and closes it; a removal by path would be refused anyway.
        #[cfg(not(windows))]
        let _ = std::fs::remove_file(p);
        false
    });
}

pub struct Sink {
    folder: PathBuf,
    wanted: String,
    mark: bool,
    file: Option<File>,
    path: Option<PathBuf>,
    finished: bool,
    written: u64,
    /// The device and inode of the file this sink created (unix), so that a discard never removes another file that has taken the name.
    #[cfg(unix)]
    made: Option<(u64, u64)>,
}

impl Sink {
    pub fn new(folder: PathBuf, name: &str, mark: bool) -> Sink {
        Sink {
            folder,
            wanted: name.to_string(),
            mark,
            file: None,
            path: None,
            finished: false,
            written: 0,
            #[cfg(unix)]
            made: None,
        }
    }

    pub fn written(&self) -> u64 {
        self.written
    }

    /// Creates the file under a free name and returns its path.
    pub fn open(&mut self) -> Result<PathBuf, SinkError> {
        // The wanted name is exactly one plain file name in the folder: no path, no drive or stream name (`D:x`, `C:\x`), no separator. The sanitizer refuses these too; this is the second guard.
        let mut parts = Path::new(&self.wanted).components();
        let one_plain_name = matches!((parts.next(), parts.next()), (Some(Component::Normal(_)), None));
        if !one_plain_name || self.wanted.chars().any(|c| matches!(c, '/' | '\\' | ':')) {
            return Err(SinkError::Io);
        }
        // A folder that depends on the working directory (HOME was not set) is not a place to receive into.
        if !self.folder.is_absolute() {
            return Err(SinkError::NoFolder);
        }
        std::fs::create_dir_all(&self.folder).map_err(|_| SinkError::NoFolder)?;
        let mut taken: Vec<String> = std::fs::read_dir(&self.folder).map(|d| d.filter_map(|e| e.ok()?.file_name().into_string().ok()).collect()).unwrap_or_default();
        for _ in 0..200 {
            let name = unique_name(&self.wanted, &taken).ok_or(SinkError::NoFreeName)?;
            let target = self.folder.join(&name);
            match create_exclusive(&target) {
                Ok(file) => {
                    #[cfg(unix)]
                    {
                        use std::os::unix::fs::MetadataExt;
                        match file.metadata() {
                            Ok(m) => self.made = Some((m.dev(), m.ino())),
                            Err(_) => {
                                // Without the identity this sink could not tell its file from another one that takes the name later: the open fails and the file goes.
                                drop(file);
                                let _ = std::fs::remove_file(&target);
                                return Err(SinkError::Io);
                            }
                        }
                    }
                    self.path = Some(target.clone());
                    partials().push(target.clone());
                    #[cfg(windows)]
                    {
                        // The mark of the web first (its stream is opened by path), then the mark for deletion through the handle. A file that cannot be marked is not handed out; it goes, partial or not.
                        let marked = !self.mark || mark_as_downloaded(&target);
                        if let Armed::Failed { err, doomed } = arm(marked, |on| doom(&file, on)) {
                            drop(file);
                            unlist(&target);
                            self.path = None;
                            if !doomed {
                                // Windows refused the mark for deletion: the one removal by path that is left, for a file that was made a moment ago.
                                let _ = std::fs::remove_file(&target);
                            }
                            return Err(err);
                        }
                    }
                    self.file = Some(file);
                    #[cfg(not(windows))]
                    {
                        // A file that cannot be marked is not handed out; it goes, partial or not.
                        if self.mark && !mark_as_downloaded(&target) {
                            self.discard();
                            return Err(SinkError::Mark);
                        }
                    }
                    return Ok(target);
                }
                Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => taken.push(name), // the volume says this name is taken: the next free one
                Err(_) => return Err(SinkError::Io),
            }
        }
        Err(SinkError::NoFreeName)
    }

    pub fn write(&mut self, data: &[u8]) -> Result<(), SinkError> {
        let file = self.file.as_mut().ok_or(SinkError::Io)?;
        file.write_all(data).map_err(|_| SinkError::Io)?;
        self.written += data.len() as u64;
        Ok(())
    }

    /// The transfer is complete: make the file ordinary, then close it. On failure the partial file is removed.
    pub fn finish(&mut self) -> Result<PathBuf, SinkError> {
        let (Some(file), Some(path)) = (self.file.take(), self.path.clone()) else { return Err(SinkError::Io) };
        let done = (|| -> std::io::Result<()> {
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                file.set_permissions(std::fs::Permissions::from_mode(0o644))?; // on the open descriptor: the very file being closed becomes ordinary
            }
            file.sync_all()?;
            #[cfg(windows)]
            {
                // Kept only if the mark for deletion comes off; if not it stays marked and closing the handle removes it.
                clear(|on| doom(&file, on)).map_err(|_| std::io::ErrorKind::Other)?;
            }
            Ok(())
        })();
        drop(file);
        unlist(&path);
        if done.is_err() {
            self.finished = false;
            self.remove_made(&path);
            self.path = None;
            return Err(SinkError::Io);
        }
        self.finished = true;
        Ok(path)
    }

    /// The transfer did not complete: close and remove the partial file. After a successful `finish` it does nothing, so a completed download stays.
    pub fn discard(&mut self) {
        if self.finished {
            return;
        }
        self.file = None;
        if let Some(path) = self.path.take() {
            unlist(&path);
            self.remove_made(&path);
        }
    }

    /// Removes `path` only while it is still the file this sink created (unix: the same device and inode), so a file the user moved away, or another that took the name, is left alone.
    /// On Windows the mark of the web (its stream) goes with the file.
    fn remove_made(&self, path: &Path) {
        #[cfg(unix)]
        {
            use std::os::unix::fs::MetadataExt;
            match (self.made, std::fs::symlink_metadata(path)) {
                (Some(made), Ok(now)) if (now.dev(), now.ino()) == made => {}
                _ => return,
            }
        }
        #[cfg(unix)]
        let _ = std::fs::remove_file(path);
        // Windows: nothing is removed by `path`. The held handle is marked for deletion, so closing it (which the caller has just done, or does now) removes the file; a path could by now be another file's.
        #[cfg(windows)]
        let _ = path;
    }
}

/// A sink released before `finish` is discarded: its partial file does not outlive it.
impl Drop for Sink {
    fn drop(&mut self) {
        self.discard();
    }
}

fn create_exclusive(path: &Path) -> std::io::Result<File> {
    let mut o = OpenOptions::new();
    o.write(true).create_new(true);
    #[cfg(windows)]
    {
        use std::os::windows::fs::OpenOptionsExt;
        // GENERIC_WRITE | DELETE, shared for reading and writing only: no FILE_SHARE_DELETE, so no other program can rename, replace or delete the file while it is held (see the header).
        o.access_mode(0x4000_0000 | 0x0001_0000).share_mode(0x1 | 0x2);
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        o.mode(0o600);
        #[cfg(target_os = "linux")]
        o.custom_flags(libc::O_NOFOLLOW | libc::O_CLOEXEC);
    }
    o.open(path)
}

/// Windows: marks the open file for deletion when its last handle closes (`on`), or takes the mark off again. Done through the handle the sink holds, never through a path. False when Windows refused.
#[cfg(windows)]
fn doom(file: &File, on: bool) -> bool {
    use std::os::windows::io::AsRawHandle;
    use windows::Win32::Foundation::HANDLE;
    use windows::Win32::Storage::FileSystem::{FileDispositionInfo, SetFileInformationByHandle, FILE_DISPOSITION_INFO};
    let info = FILE_DISPOSITION_INFO { DeleteFile: on };
    // SAFETY: the handle stays open while `file` is borrowed, and `info` is a live FILE_DISPOSITION_INFO of exactly the size passed.
    unsafe { SetFileInformationByHandle(HANDLE(file.as_raw_handle()), FileDispositionInfo, std::ptr::from_ref(&info).cast(), std::mem::size_of::<FILE_DISPOSITION_INFO>() as u32).is_ok() }
}

#[cfg(windows)]
fn stream_path(file: &Path) -> PathBuf {
    let mut s = file.as_os_str().to_owned();
    s.push(":Zone.Identifier");
    PathBuf::from(s)
}

/// Windows: the mark of the web, zone 3 (the Internet), so that Explorer, SmartScreen and Office treat the file as downloaded. Not Windows: nothing to do.
#[cfg(windows)]
fn mark_as_downloaded(file: &Path) -> bool {
    std::fs::write(stream_path(file), "[ZoneTransfer]\r\nZoneId=3\r\n").is_ok()
}

#[cfg(not(windows))]
fn mark_as_downloaded(_file: &Path) -> bool {
    true
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SourceError {
    NotAFile,
    TooLarge,
    NameTooLong,
    Unreadable,
}

/// A file read to be sent: a regular file of at most 4 GiB whose name fits the wire. A folder, a device, a link to either and a file that is too big are refused when the user clicks Send.
pub struct Source {
    pub path: PathBuf,
    pub name: String,
    pub size: u64,
    pub kind: String,
    file: Option<File>,
}

impl Source {
    pub fn open(path: &Path) -> Result<Source, SourceError> {
        let mut o = OpenOptions::new();
        o.read(true);
        #[cfg(target_os = "linux")]
        {
            use std::os::unix::fs::OpenOptionsExt;
            o.custom_flags(libc::O_NONBLOCK | libc::O_CLOEXEC); // a FIFO swapped in after a name check cannot block this open
        }
        let file = o.open(path).map_err(|e| if e.kind() == std::io::ErrorKind::NotFound { SourceError::NotAFile } else { SourceError::Unreadable })?;
        let meta = file.metadata().map_err(|_| SourceError::Unreadable)?; // what was opened is checked, not the name
        if !meta.is_file() {
            return Err(SourceError::NotAFile);
        }
        if meta.len() > SIZE_MAX {
            return Err(SourceError::TooLarge);
        }
        let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("").to_string();
        if name.is_empty() || name.len() > RAW_NAME_MAX {
            return Err(SourceError::NameTooLong);
        }
        let kind = mime_for(path.extension().and_then(|e| e.to_str()).unwrap_or("")).to_string();
        Ok(Source { path: path.to_path_buf(), name, size: meta.len(), kind, file: Some(file) })
    }

    /// The next piece, up to `count` bytes; empty at the end of the file.
    pub fn read(&mut self, count: usize) -> Result<Vec<u8>, SourceError> {
        let file = self.file.as_mut().ok_or(SourceError::Unreadable)?;
        let mut buf = vec![0u8; count];
        let mut filled = 0;
        while filled < count {
            match file.read(&mut buf[filled..]) {
                Ok(0) => break,
                Ok(n) => filled += n,
                Err(e) if e.kind() == std::io::ErrorKind::Interrupted => {}
                Err(_) => return Err(SourceError::Unreadable),
            }
        }
        buf.truncate(filled);
        Ok(buf)
    }

    pub fn close(&mut self) {
        self.file = None;
    }
}

/// The file's type by its extension: advisory only (the receiver never decides anything by it), printable ASCII, empty when unknown.
fn mime_for(ext: &str) -> &'static str {
    match ext.to_ascii_lowercase().as_str() {
        "txt" | "log" => "text/plain",
        "md" => "text/markdown",
        "html" | "htm" => "text/html",
        "csv" => "text/csv",
        "json" => "application/json",
        "pdf" => "application/pdf",
        "zip" => "application/zip",
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "gif" => "image/gif",
        "webp" => "image/webp",
        "svg" => "image/svg+xml",
        "mp3" => "audio/mpeg",
        "wav" => "audio/wav",
        "mp4" => "video/mp4",
        "mov" => "video/quicktime",
        _ => "",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};

    static COUNTER: AtomicU64 = AtomicU64::new(0);

    fn temp(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("notchmeow-link-{tag}-{}-{}", std::process::id(), COUNTER.fetch_add(1, Ordering::Relaxed)));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn registered(p: &Path) -> bool {
        partials().iter().any(|q| q == p)
    }

    fn names(dir: &Path) -> Vec<String> {
        let mut v: Vec<String> = std::fs::read_dir(dir).unwrap().map(|e| e.unwrap().file_name().into_string().unwrap()).collect();
        v.sort();
        v
    }

    #[test]
    fn a_file_is_created_written_and_finished() {
        let dir = temp("sink");
        let mut s = Sink::new(dir.join("NotchMeow"), "a.txt", false);
        let path = s.open().unwrap();
        s.write(b"hello ").unwrap();
        s.write(b"world").unwrap();
        assert_eq!(s.written(), 11);
        let done = s.finish().unwrap();
        assert_eq!(done, path);
        assert_eq!(std::fs::read(&done).unwrap(), b"hello world");
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(std::fs::metadata(&done).unwrap().permissions().mode() & 0o777, 0o644, "ordinary once complete");
        }
        drop(s);
        assert!(done.exists(), "a completed download stays when the sink is dropped");
    }

    #[test]
    fn a_name_that_is_taken_is_numbered_and_nothing_is_overwritten() {
        let dir = temp("taken");
        std::fs::write(dir.join("a.txt"), "mine").unwrap();
        let mut s = Sink::new(dir.clone(), "a.txt", false);
        let path = s.open().unwrap();
        assert_eq!(path.file_name().unwrap(), "a (1).txt");
        s.write(b"x").unwrap();
        s.finish().unwrap();
        assert_eq!(std::fs::read(dir.join("a.txt")).unwrap(), b"mine");
        let mut again = Sink::new(dir.clone(), "A.TXT", false);
        assert_eq!(again.open().unwrap().file_name().unwrap(), "A (2).TXT", "case does not matter on the volumes that fold it");
    }

    #[cfg(unix)]
    #[test]
    fn a_link_with_the_wanted_name_is_not_followed() {
        let dir = temp("link");
        let elsewhere = temp("elsewhere").join("victim.txt");
        std::fs::write(&elsewhere, "keep").unwrap();
        std::os::unix::fs::symlink(&elsewhere, dir.join("a.txt")).unwrap();
        let mut s = Sink::new(dir.clone(), "a.txt", false);
        let path = s.open().unwrap();
        s.write(b"new").unwrap();
        s.finish().unwrap();
        assert_eq!(path.file_name().unwrap(), "a (1).txt");
        assert_eq!(std::fs::read(&elsewhere).unwrap(), b"keep");
    }

    #[test]
    fn a_dangling_link_with_the_wanted_name_is_not_followed_either() {
        #[cfg(unix)]
        {
            let dir = temp("dangling");
            std::os::unix::fs::symlink(dir.join("nowhere"), dir.join("a.txt")).unwrap();
            let mut s = Sink::new(dir.clone(), "a.txt", false);
            assert_eq!(s.open().unwrap().file_name().unwrap(), "a (1).txt");
            assert!(!dir.join("nowhere").exists(), "nothing was created through the link");
        }
    }

    #[test]
    fn a_transfer_that_does_not_complete_leaves_no_file() {
        let dir = temp("discard");
        let mut s = Sink::new(dir.clone(), "a.bin", false);
        s.open().unwrap();
        s.write(&[1, 2, 3]).unwrap();
        s.discard();
        assert!(names(&dir).is_empty());
        let mut d = Sink::new(dir.clone(), "b.bin", false);
        d.open().unwrap();
        drop(d);
        assert!(names(&dir).is_empty(), "a sink dropped before finish is discarded");
        let mut f = Sink::new(dir.clone(), "c.bin", false);
        f.open().unwrap();
        f.write(&[1]).unwrap();
        f.finish().unwrap();
        f.discard();
        assert_eq!(names(&dir), vec!["c.bin"], "discard after finish does not delete the completed file");
    }

    #[test]
    fn a_file_the_user_moved_away_is_not_confused_with_another_that_took_its_name() {
        #[cfg(unix)]
        {
            let dir = temp("moved");
            let mut s = Sink::new(dir.clone(), "a.bin", false);
            let path = s.open().unwrap();
            std::fs::rename(&path, dir.join("moved.bin")).unwrap();
            std::fs::write(&path, "somebody else's").unwrap();
            s.discard();
            assert_eq!(std::fs::read(&path).unwrap(), b"somebody else's");
        }
    }

    #[test]
    fn a_name_that_is_a_path_is_refused_by_the_sink_itself() {
        let dir = temp("path");
        for bad in ["../x", "a/b", "a\\b", "..", "."] {
            assert_eq!(Sink::new(dir.clone(), bad, false).open().unwrap_err(), SinkError::Io, "{bad}");
        }
        assert!(names(&dir).is_empty());
    }

    #[test]
    fn a_wanted_name_is_one_plain_file_name_and_nothing_else() {
        let dir = temp("plain");
        for bad in ["a/b", "a\\b", "a/", "../x", "..", ".", "", "D:x", "C:\\x", "C:", "a:b"] {
            assert_eq!(Sink::new(dir.clone(), bad, false).open().unwrap_err(), SinkError::Io, "{bad}");
        }
        assert!(names(&dir).is_empty(), "nothing was created for a refused name");
    }

    #[test]
    fn a_source_is_a_regular_file_only() {
        let dir = temp("source");
        let file = dir.join("hello.pdf");
        std::fs::write(&file, vec![9u8; 70_000]).unwrap();
        let mut src = Source::open(&file).unwrap();
        assert_eq!((src.name.as_str(), src.size, src.kind.as_str()), ("hello.pdf", 70_000, "application/pdf"));
        assert_eq!(src.read(32768).unwrap().len(), 32768);
        assert_eq!(src.read(32768).unwrap().len(), 32768);
        assert_eq!(src.read(32768).unwrap().len(), 4464);
        assert!(src.read(32768).unwrap().is_empty(), "empty at the end");
        #[cfg(unix)]
        assert_eq!(Source::open(&dir).err(), Some(SourceError::NotAFile), "a folder");
        #[cfg(windows)]
        assert!(Source::open(&dir).is_err(), "a folder");
        assert_eq!(Source::open(&dir.join("gone")).err(), Some(SourceError::NotAFile));
        std::fs::write(dir.join("no-type"), "x").unwrap();
        assert_eq!(Source::open(&dir.join("no-type")).unwrap().kind, "");
        #[cfg(unix)]
        {
            std::os::unix::fs::symlink(&dir, dir.join("link-to-folder")).unwrap();
            assert_eq!(Source::open(&dir.join("link-to-folder")).err(), Some(SourceError::NotAFile), "a link to a folder");
            assert_eq!(Source::open(Path::new("/dev/null")).err(), Some(SourceError::NotAFile), "a device");
        }
    }

    #[test]
    fn a_clean_quit_removes_the_partial_file_of_a_receive_in_progress_and_only_that() {
        let dir = temp("quit");
        let mut partial = Sink::new(dir.clone(), "partial.bin", false);
        let partial_path = partial.open().unwrap();
        partial.write(&[1, 2, 3]).unwrap();
        let mut done = Sink::new(dir.clone(), "done.bin", false);
        let done_path = done.open().unwrap();
        done.write(&[4]).unwrap();
        done.finish().unwrap();
        assert!(registered(&partial_path) && !registered(&done_path), "the partial one is listed and the finished one is not");
        remove_partials_matching(|p| p.starts_with(&dir));
        // The sink stays alive here, so its Drop (discard, which would also remove the file by path) cannot be what removed it.
        // A deleted file that is still open cannot be read, so `read` is the check. On Windows nothing is removed by path (the sink's handle is marked for deletion): the file goes when the sink does.
        #[cfg(not(windows))]
        assert!(std::fs::read(&partial_path).is_err(), "the partial file is gone");
        assert_eq!(std::fs::read(&done_path).unwrap(), [4], "a completed file stays");
        assert!(!registered(&partial_path));
        drop(partial); // its own discard finds nothing left and does no harm
        assert_eq!(names(&dir), vec!["done.bin"]);
    }

    #[test]
    fn the_list_of_partial_files_is_cleared_by_finish_discard_and_drop() {
        let dir = temp("registry");
        let mut a = Sink::new(dir.clone(), "a.bin", false);
        let pa = a.open().unwrap();
        assert!(registered(&pa));
        a.finish().unwrap();
        assert!(!registered(&pa), "finish");
        let mut b = Sink::new(dir.clone(), "b.bin", false);
        let pb = b.open().unwrap();
        assert!(registered(&pb));
        b.discard();
        assert!(!registered(&pb), "discard");
        let mut c = Sink::new(dir.clone(), "c.bin", false);
        let pc = c.open().unwrap();
        assert!(registered(&pc));
        drop(c);
        assert!(!registered(&pc), "drop");
    }

    #[test]
    fn a_file_is_marked_for_deletion_after_its_mark_of_the_web_and_every_failure_ends_in_a_deletion() {
        let calls = std::cell::RefCell::new(Vec::new());
        assert_eq!(
            arm(true, |on| {
                calls.borrow_mut().push(on);
                true
            }),
            Armed::Ready
        );
        assert_eq!(*calls.borrow(), [true], "marked for deletion once");
        assert_eq!(arm(false, |_| true), Armed::Failed { err: SinkError::Mark, doomed: true }, "no mark of the web: not handed out, and it goes with its handle");
        assert_eq!(arm(true, |_| false), Armed::Failed { err: SinkError::Io, doomed: false }, "Windows refused the mark: the caller removes the new file");
        assert_eq!(arm(false, |_| false), Armed::Failed { err: SinkError::Mark, doomed: false });
    }

    #[test]
    fn a_file_is_kept_only_if_the_mark_for_deletion_comes_off() {
        assert_eq!(
            clear(|on| {
                assert!(!on, "clearing asks for no deletion");
                true
            }),
            Ok(())
        );
        assert_eq!(clear(|_| false), Err(SinkError::Io), "it stays marked, so closing the handle removes it: the download fails closed");
    }

    // The next three run on Windows only (CI and the owner): they need the real handle.
    #[cfg(windows)]
    #[test]
    fn a_file_in_progress_cannot_be_deleted_renamed_or_replaced_by_anybody_else() {
        let dir = temp("held");
        let mut s = Sink::new(dir.clone(), "a.bin", false);
        let path = s.open().unwrap();
        s.write(&[1, 2, 3]).unwrap();
        assert!(std::fs::remove_file(&path).is_err(), "no delete by path while the sink holds it");
        assert!(std::fs::rename(&path, dir.join("moved.bin")).is_err(), "no rename");
        s.discard();
        assert!(names(&dir).is_empty(), "and the discard removed it through the handle");
    }

    #[cfg(windows)]
    #[test]
    fn a_marked_file_carries_the_mark_of_the_web_when_finished_and_takes_it_along_when_discarded() {
        let dir = temp("zone");
        let mut s = Sink::new(dir.clone(), "a.txt", true);
        let path = s.open().unwrap();
        s.write(b"hi").unwrap();
        let done = s.finish().unwrap();
        assert_eq!(std::fs::read(&done).unwrap(), b"hi");
        assert!(std::fs::read_to_string(stream_path(&path)).unwrap().contains("ZoneId=3"), "the mark of the web");
        drop(s);
        assert!(done.exists(), "a finished download stays");
        let mut d = Sink::new(dir.clone(), "b.txt", true);
        d.open().unwrap();
        d.write(b"x").unwrap();
        d.discard();
        assert_eq!(names(&dir), vec!["a.txt"], "the discarded one is gone, stream and all");
    }

    #[cfg(windows)]
    #[test]
    fn another_file_that_takes_the_name_after_a_completed_download_is_never_touched_by_a_later_discard() {
        let dir = temp("later");
        let mut s = Sink::new(dir.clone(), "a.bin", false);
        let path = s.open().unwrap();
        s.finish().unwrap();
        std::fs::remove_file(&path).unwrap();
        std::fs::write(&path, "somebody else's").unwrap();
        s.discard();
        drop(s);
        assert_eq!(std::fs::read(&path).unwrap(), b"somebody else's");
    }

    #[test]
    fn a_relative_folder_is_not_a_place_to_receive_into() {
        let name = format!("notchmeow-relative-{}", std::process::id());
        let mut s = Sink::new(PathBuf::from(&name).join("NotchMeow"), "a.bin", false);
        assert_eq!(s.open().unwrap_err(), SinkError::NoFolder, "a folder that depends on the working directory (HOME was not set) is refused");
        assert!(!Path::new(&name).exists(), "and nothing was made in the working directory");
    }

    #[cfg(not(windows))]
    #[test]
    fn the_xdg_download_folder_is_read_from_user_dirs() {
        let home = Path::new("/home/sam");
        assert_eq!(parse_user_dirs("XDG_DOCUMENTS_DIR=\"$HOME/Docs\"\nXDG_DOWNLOAD_DIR=\"$HOME/Telechargements\"\n", home), Some(PathBuf::from("/home/sam/Telechargements")));
        assert_eq!(parse_user_dirs("XDG_DOWNLOAD_DIR=\"/data/dl\"", home), Some(PathBuf::from("/data/dl")));
        assert_eq!(parse_user_dirs("XDG_DOWNLOAD_DIR=\"$HOME/\"", home), None, "the home folder itself is not a download folder");
        assert_eq!(parse_user_dirs("XDG_DOWNLOAD_DIR=\"relative\"", home), None);
        assert_eq!(parse_user_dirs("", home), None);
    }

    #[test]
    fn the_default_folder_ends_in_downloads_notchmeow() {
        let f = default_folder();
        assert_eq!(f.file_name().unwrap(), "NotchMeow");
    }
}
