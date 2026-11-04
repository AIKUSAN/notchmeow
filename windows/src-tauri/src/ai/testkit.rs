// Test helpers shared by the ai tests: the shared fixtures, Python, and the fake
// model server from tests/fake_local_llm.py. Compiled for `cargo test` only.

use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicU32, Ordering};
use std::time::{Duration, Instant};

use serde_json::Value;

/// tests/fixtures/ai at the repository root.
pub fn fixtures_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../tests/fixtures/ai")
}

pub fn load_json(name: &str) -> Value {
    let path = fixtures_dir().join(name);
    let text = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
    serde_json::from_str(&text).unwrap_or_else(|e| panic!("parse {}: {e}", path.display()))
}

/// `python3` on Linux and macOS, `python` (or the `py` launcher) on Windows runners.
pub fn python() -> Command {
    for (exe, args) in [("python3", &[][..]), ("python", &[][..]), ("py", &["-3"][..])] {
        let ok = Command::new(exe)
            .args(args)
            .arg("--version")
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .map(|s| s.success())
            .unwrap_or(false);
        if ok {
            let mut cmd = Command::new(exe);
            cmd.args(args);
            return cmd;
        }
    }
    panic!("Python 3 is needed for the AI tests (python3, python or py -3)");
}

/// Tests that start a fake `claude` hold this shared for as long as it runs; a test that calls `claude_run::stop_all`
/// (which ends every live run of the process) holds it alone, so it can only ever stop its own.
#[cfg(unix)]
static CLAUDE_RUNS: std::sync::RwLock<()> = std::sync::RwLock::new(());

#[cfg(unix)]
pub fn claude_runs_shared() -> std::sync::RwLockReadGuard<'static, ()> {
    CLAUDE_RUNS.read().unwrap_or_else(std::sync::PoisonError::into_inner)
}

#[cfg(unix)]
pub fn claude_runs_alone() -> std::sync::RwLockWriteGuard<'static, ()> {
    CLAUDE_RUNS.write().unwrap_or_else(std::sync::PoisonError::into_inner)
}

static COUNTER: AtomicU32 = AtomicU32::new(0);

/// A fresh, empty temporary directory, removed when dropped.
pub struct TempDir(pub PathBuf);

impl TempDir {
    pub fn new(tag: &str) -> Self {
        let n = COUNTER.fetch_add(1, Ordering::Relaxed);
        let dir = std::env::temp_dir().join(format!("nm-ai-{tag}-{}-{n}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        TempDir(dir)
    }

    pub fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

/// Runs tests/fixtures/ai/make_attachments.py into a temporary directory.
pub fn make_attachments() -> TempDir {
    let dir = TempDir::new("att");
    let status = python()
        .arg(fixtures_dir().join("make_attachments.py"))
        .arg(dir.path())
        .status()
        .expect("run make_attachments.py");
    assert!(status.success(), "make_attachments.py failed");
    dir
}

/// tests/fake_local_llm.py on a free port, killed when dropped.
pub struct FakeServer {
    pub base: String,
    log: PathBuf,
    child: Child,
    _dir: TempDir,
}

impl FakeServer {
    /// `flags` are the server's own: `--persona ollama`, `--fail 429`, `--delay 2`…
    pub fn start(flags: &[&str]) -> Self {
        let dir = TempDir::new("fake");
        let port_file = dir.path().join("port");
        let log = dir.path().join("requests.jsonl");
        let script = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../tests/fake_local_llm.py");
        let child = python()
            .arg(script)
            .arg(&port_file)
            .arg("--log")
            .arg(&log)
            .args(flags)
            .stdout(Stdio::null())
            .stderr(Stdio::inherit())
            .spawn()
            .expect("start the fake server");
        let started = Instant::now();
        loop {
            if let Ok(port) = std::fs::read_to_string(&port_file) {
                if !port.trim().is_empty() {
                    // The port is written just before serve_forever; give it a moment to listen.
                    std::thread::sleep(Duration::from_millis(50));
                    return FakeServer { base: format!("http://127.0.0.1:{}", port.trim()), log, child, _dir: dir };
                }
            }
            assert!(started.elapsed() < Duration::from_secs(10), "fake server did not start");
            std::thread::sleep(Duration::from_millis(20));
        }
    }

    /// Every request the server received: `{method, path, origin, body}`.
    pub fn requests(&self) -> Vec<Value> {
        std::fs::read_to_string(&self.log)
            .unwrap_or_default()
            .lines()
            .filter_map(|l| serde_json::from_str(l).ok())
            .collect()
    }
}

impl Drop for FakeServer {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

/// A server that answers every request with one fixed response, for what the fake model
/// server can't produce: a rejected key on `GET /v1/models`, a stream that ends inside
/// `<think>`. Returns its base URL; it runs until the test process exits.
pub fn canned_server(status: u16, content_type: &str, body: &str) -> String {
    use std::io::{Read, Write};
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let base = format!("http://{}", listener.local_addr().unwrap());
    let response = format!(
        "HTTP/1.1 {status} Canned\r\nContent-Type: {content_type}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
        body.len()
    );
    std::thread::spawn(move || {
        for mut stream in listener.incoming().flatten() {
            // Read the whole request first (headers, then the body) so the client never sees a reset.
            let mut seen = Vec::new();
            let mut chunk = [0u8; 4096];
            let mut want: Option<usize> = None;
            loop {
                let n = match stream.read(&mut chunk) {
                    Ok(0) | Err(_) => break,
                    Ok(n) => n,
                };
                seen.extend_from_slice(&chunk[..n]);
                if want.is_none() {
                    if let Some(end) = seen.windows(4).position(|w| w == b"\r\n\r\n") {
                        let head = String::from_utf8_lossy(&seen[..end]).to_ascii_lowercase();
                        let length = head
                            .lines()
                            .find_map(|l| l.strip_prefix("content-length:"))
                            .and_then(|v| v.trim().parse::<usize>().ok())
                            .unwrap_or(0);
                        want = Some(end + 4 + length);
                    }
                }
                if want.is_some_and(|w| seen.len() >= w) {
                    break;
                }
            }
            let _ = stream.write_all(response.as_bytes());
            let _ = stream.flush();
        }
    });
    base
}

/// A fixture file under tests/fixtures/ai/sse/.
pub fn sse_fixture(format: &str, name: &str) -> String {
    std::fs::read_to_string(fixtures_dir().join("sse").join(format).join(name)).unwrap()
}

/// One SSE answer whose events arrive on a schedule: `(wait before it, the `data:` payload)`.
/// For tests that run on tokio's paused clock (`start_paused`), so minutes of silence cost
/// nothing. Its own tokio tasks, so it must run inside the test's runtime. Returns its base URL.
pub async fn paced_sse_server(script: Vec<(Duration, String)>) -> String {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let base = format!("http://{}", listener.local_addr().unwrap());
    tokio::spawn(async move {
        let Ok((mut stream, _)) = listener.accept().await else { return };
        let mut seen = Vec::new();
        let mut chunk = [0u8; 4096];
        let mut want: Option<usize> = None;
        while want.map_or(true, |w| seen.len() < w) {
            let Ok(n) = stream.read(&mut chunk).await else { return };
            if n == 0 {
                return;
            }
            seen.extend_from_slice(&chunk[..n]);
            if want.is_none() {
                if let Some(end) = seen.windows(4).position(|w| w == b"\r\n\r\n") {
                    let head = String::from_utf8_lossy(&seen[..end]).to_ascii_lowercase();
                    let length = head
                        .lines()
                        .find_map(|l| l.strip_prefix("content-length:"))
                        .and_then(|v| v.trim().parse::<usize>().ok())
                        .unwrap_or(0);
                    want = Some(end + 4 + length);
                }
            }
        }
        let head = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nTransfer-Encoding: chunked\r\n\r\n";
        if stream.write_all(head.as_bytes()).await.is_err() {
            return;
        }
        for (wait, data) in script {
            tokio::time::sleep(wait).await;
            let event = format!("data: {data}\n\n");
            if stream.write_all(format!("{:x}\r\n{event}\r\n", event.len()).as_bytes()).await.is_err() {
                return;
            }
        }
        let _ = stream.write_all(b"0\r\n\r\n").await;
    });
    base
}
