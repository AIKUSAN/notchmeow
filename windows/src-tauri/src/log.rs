// Small append-only log at %LOCALAPPDATA%\NotchMeow\notchmeow.log (Windows) or
// ~/.local/share/notchmeow/notchmeow.log (Linux) — the equivalent of nbLog() in
// HookServer.swift. Nothing leaves the machine.

/// Every line, in tests: the leak test checks that no prompt or file reaches the log.
#[cfg(test)]
pub static CAPTURED: std::sync::Mutex<Vec<String>> = std::sync::Mutex::new(Vec::new());

/// In tests a line is recorded in `CAPTURED` and never written: tests must not touch a real log.
pub fn line(message: impl AsRef<str>) {
    #[cfg(test)]
    CAPTURED.lock().unwrap().push(message.as_ref().to_string());
    #[cfg(not(test))]
    write(message.as_ref());
}

#[cfg(not(test))]
fn write(message: &str) {
    use std::io::Write;

    use crate::{platform, settings};

    let t = platform::local_time();
    let stamp = format!(
        "{:04}-{:02}-{:02} {:02}:{:02}:{:02}",
        t.year, t.month, t.day, t.hour, t.minute, t.second
    );
    let dir = settings::local_dir();
    if platform::ensure_private_dir(&dir).is_err() {
        return;
    }
    let path = dir.join("notchmeow.log");
    // Keep it from growing forever: start fresh past ~1 MB.
    if std::fs::metadata(&path).map(|m| m.len() > 1_000_000).unwrap_or(false) {
        let _ = std::fs::remove_file(&path);
    }
    let mut options = std::fs::OpenOptions::new();
    options.create(true).append(true);
    // Readable by us only, like the macOS log.
    #[cfg(unix)]
    std::os::unix::fs::OpenOptionsExt::mode(&mut options, 0o600);
    if let Ok(mut file) = options.open(path) {
        let _ = writeln!(file, "{stamp} {message}");
    }
}
