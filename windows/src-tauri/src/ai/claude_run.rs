// Claude Code as a provider: one `claude -p` process per turn. This file owns the process; the command line and the
// meaning of the transcript are in `claude_code.rs`. std::process only (no tokio `process` feature, no new crate).
//
// Nothing runs on a timer. A turn starts one process and ends when it does; Stop (the turn's future being dropped)
// interrupts it, then terminates it, then kills it and everything it started, so no process outlives the chat. Nothing is
// logged but event types and error kinds: never the arguments, the folder, stdin, stdout, stderr or the environment.

use std::io::{BufRead, BufReader, Write};
use std::path::Path;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use tokio::sync::mpsc::unbounded_channel;

use crate::ai::claude_cli;
use crate::ai::claude_code::{self, Stream, Turn, FOLDER_MISSING, MISSING, MODELS};
use crate::ai::provider::{
    Aggregate, AiError, BoxFuture, Capabilities, ChatChunk, ChatRequest, ErrorKind, Finish, ModelInfo, ModelProvider, Placement, Role,
};
use crate::log;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Timings {
    /// How long to wait for the run's first line. Claude Code says `system/init` within a second or two; after that it
    /// may take as long as it needs (a build can run for minutes).
    pub startup: Duration,
    /// Stop: the wait after the interrupt before the group is terminated, and after that before it is killed.
    pub interrupt_grace: Duration,
    pub terminate_grace: Duration,
    /// How long a pipe may stay open after the process exited (a grandchild that kept it).
    pub drain: Duration,
}

impl Default for Timings {
    fn default() -> Self {
        Timings {
            startup: Duration::from_secs(30),
            interrupt_grace: Duration::from_secs(2),
            terminate_grace: Duration::from_secs(2),
            drain: Duration::from_secs(1),
        }
    }
}

/// Everything one turn needs to run Claude Code, besides the message.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Run {
    /// The program: found by `claude_cli::locate`, never modified.
    pub executable: String,
    /// Arguments before the turn's own. Empty, except in tests that run the fake through an interpreter.
    pub leading_args: Vec<String>,
    pub turn: Turn,
    /// Where chat-only runs happen: a folder NotchMeow owns and keeps empty.
    pub chat_folder: String,
    /// A recap of the chat so far, for a session started afresh in the middle of it.
    pub preamble: Option<String>,
    /// The caller's environment, from which the run's is made.
    pub base_env: Vec<(String, String)>,
    pub timings: Timings,
}

pub struct ClaudeCode {
    run: Run,
}

impl ClaudeCode {
    pub fn new(run: Run) -> Self {
        ClaudeCode { run }
    }
}

enum Msg {
    Line(String),
    /// stdout ended.
    OutEof,
    /// stderr ended.
    ErrEof,
    Exited,
}

/// Stops the process when it is dropped: the turn's future is dropped on Stop. Safe to call twice, or after the process
/// ended.
struct StopGuard {
    pid: u32,
    exited: Arc<AtomicBool>,
    stopped: AtomicBool,
    timings: Timings,
}

impl StopGuard {
    fn stop(&self) {
        if self.exited.load(Ordering::SeqCst) || self.stopped.swap(true, Ordering::SeqCst) {
            return;
        }
        stop_process_tree(self.pid, self.timings, self.exited.clone());
    }
}

impl Drop for StopGuard {
    fn drop(&mut self) {
        self.stop();
    }
}

/// Windows has no interrupt to give a console child: the tree goes at once.
#[cfg(windows)]
fn stop_process_tree(pid: u32, _timings: Timings, _exited: Arc<AtomicBool>) {
    claude_cli::taskkill_tree(pid);
}

/// Interrupt first (Claude Code ends the tool it is running), then terminate, then kill: the whole process group, so
/// whatever the run started goes too. The run was started as its own group leader.
#[cfg(unix)]
fn stop_process_tree(pid: u32, timings: Timings, _exited: Arc<AtomicBool>) {
    let group = -(pid as i32);
    let gone = move || unsafe { libc::kill(group, 0) != 0 };
    unsafe { libc::kill(group, libc::SIGINT) };
    std::thread::spawn(move || {
        let wait = |grace: Duration| {
            let start = std::time::Instant::now();
            while !gone() && start.elapsed() < grace {
                std::thread::sleep(Duration::from_millis(20));
            }
        };
        wait(timings.interrupt_grace);
        if gone() {
            return;
        }
        unsafe { libc::kill(group, libc::SIGTERM) };
        wait(timings.terminate_grace);
        if !gone() {
            unsafe { libc::kill(group, libc::SIGKILL) };
        }
    });
}

/// The runs whose process has been launched and has not exited: (pid, "the process has exited"). Process-wide, so that
/// quitting the app can end them: `StopGuard::drop` does not run when the process exits.
static LIVE: Mutex<Vec<(u32, Arc<AtomicBool>)>> = Mutex::new(Vec::new());

fn live() -> std::sync::MutexGuard<'static, Vec<(u32, Arc<AtomicBool>)>> {
    LIVE.lock().unwrap_or_else(std::sync::PoisonError::into_inner)
}

#[cfg(all(test, unix))]
fn live_count() -> usize {
    live().len()
}

/// Quit: ends every running `claude` and what it started, and returns when they are gone or at the latest about a second
/// later. Synchronous, for the app's exit handler. Unix: SIGINT to each group, a wait of up to a second in all, then
/// SIGKILL to each group. Windows: the whole tree at once.
pub fn stop_all() {
    let runs: Vec<(u32, Arc<AtomicBool>)> = live().clone();
    if runs.is_empty() {
        return;
    }
    #[cfg(windows)]
    for (pid, exited) in &runs {
        if !exited.load(Ordering::SeqCst) {
            claude_cli::taskkill_tree(*pid);
        }
    }
    #[cfg(unix)]
    {
        let group = |pid: u32| -(pid as i32);
        for (pid, _) in &runs {
            unsafe { libc::kill(group(*pid), libc::SIGINT) };
        }
        let end = std::time::Instant::now() + Duration::from_secs(1);
        while std::time::Instant::now() < end && !runs.iter().all(|(_, exited)| exited.load(Ordering::SeqCst)) {
            std::thread::sleep(Duration::from_millis(20));
        }
        // Whatever the run started may outlive it (and ignore the interrupt): the group is killed unless the process was
        // reaped and nothing of its group is left (then the number could be another group's).
        for (pid, exited) in &runs {
            if !exited.load(Ordering::SeqCst) || unsafe { libc::kill(group(*pid), 0) } == 0 {
                unsafe { libc::kill(group(*pid), libc::SIGKILL) };
            }
        }
    }
}

impl ModelProvider for ClaudeCode {
    fn id(&self) -> &str {
        "claudeCode"
    }

    fn display_name(&self) -> &str {
        "Claude plan"
    }

    fn placement(&self) -> Placement {
        Placement::Cloud
    }

    fn list_models(&self) -> BoxFuture<'_, Result<Vec<ModelInfo>, AiError>> {
        Box::pin(async {
            Ok(MODELS
                .iter()
                .map(|m| ModelInfo {
                    id: m.to_string(),
                    display_name: format!("Claude {}{}", m[..1].to_uppercase(), &m[1..]),
                    context_tokens: None,
                    capabilities: Capabilities { tools: true, vision: true, json: false },
                })
                .collect())
        })
    }

    fn stream<'a>(
        &'a self,
        request: &'a ChatRequest,
        sink: &'a mut (dyn FnMut(ChatChunk) + Send),
    ) -> BoxFuture<'a, Result<Aggregate, AiError>> {
        Box::pin(self.execute(request, sink))
    }
}

impl ClaudeCode {
    async fn execute(&self, request: &ChatRequest, sink: &mut (dyn FnMut(ChatChunk) + Send)) -> Result<Aggregate, AiError> {
        let run = &self.run;
        let cwd = claude_code::working_directory(&run.turn, &run.chat_folder);
        if run.turn.level.folder().is_none() {
            let _ = std::fs::create_dir_all(&cwd);
        }
        if !Path::new(&cwd).is_dir() {
            return Err(AiError { code: Some(FOLDER_MISSING.into()), ..AiError::new(ErrorKind::BadRequest) });
        }
        let Some(message) = request.messages.iter().rev().find(|m| m.role == Role::User) else {
            return Err(AiError::new(ErrorKind::BadRequest));
        };
        let line = claude_code::user_line(&message.parts, run.preamble.as_deref());

        let mut cmd = Command::new(&run.executable);
        cmd.args(&run.leading_args)
            .args(claude_code::arguments(&run.turn))
            .env_clear()
            .envs(claude_cli::child_environment(run.base_env.clone(), run.turn.platform, &run.executable))
            .current_dir(&cwd)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        crate::platform::no_console(&mut cmd);
        #[cfg(unix)]
        {
            use std::os::unix::process::CommandExt;
            cmd.process_group(0);
        }
        // Stop is this future being dropped, and a future is only ever dropped between two of its polls. Nothing here awaits
        // between the spawn and the guard below, so a Stop either comes before the process exists (the future was never
        // polled: nothing is started) or finds a guard that will end it. No flag is needed, and none can fall between
        // "started" and "can be stopped". A test cancels runs at every moment of the launch to hold this.
        let Ok(mut child) = cmd.spawn() else {
            return Err(AiError { code: Some(MISSING.into()), ..AiError::new(ErrorKind::Unreachable) });
        };

        let exited = Arc::new(AtomicBool::new(false));
        live().push((child.id(), exited.clone()));
        let guard = StopGuard { pid: child.id(), exited: exited.clone(), stopped: AtomicBool::new(false), timings: run.timings };
        let (tx, mut rx) = unbounded_channel::<Msg>();

        // Written on its own thread: a large PDF must not wait for the pipe while the reply is being read.
        let mut stdin = child.stdin.take().expect("piped");
        std::thread::spawn(move || {
            let _ = stdin.write_all(line.as_bytes());
        });
        let stdout = child.stdout.take().expect("piped");
        let lines = tx.clone();
        std::thread::spawn(move || {
            let mut reader = BufReader::new(stdout);
            let mut buf = Vec::new();
            loop {
                buf.clear();
                match reader.read_until(b'\n', &mut buf) {
                    Ok(0) | Err(_) => break,
                    Ok(_) => {
                        let text = String::from_utf8_lossy(&buf);
                        if lines.send(Msg::Line(text.trim_end_matches(['\n', '\r']).to_string())).is_err() {
                            return;
                        }
                    }
                }
            }
            let _ = lines.send(Msg::OutEof);
        });
        let errors = Arc::new(Mutex::new(Vec::<u8>::new()));
        let stderr = child.stderr.take().expect("piped");
        let sink_errors = errors.clone();
        let errors_done = tx.clone();
        std::thread::spawn(move || {
            let mut reader = BufReader::new(stderr);
            let mut buf = Vec::new();
            while let Ok(n) = reader.read_until(b'\n', &mut buf) {
                if n == 0 {
                    break;
                }
                let mut all = sink_errors.lock().unwrap();
                if all.len() < 65_536 {
                    all.extend_from_slice(&buf);
                }
                buf.clear();
            }
            let _ = errors_done.send(Msg::ErrEof);
        });
        let done = exited.clone();
        std::thread::spawn(move || {
            let pid = child.id();
            let _ = child.wait();
            done.store(true, Ordering::SeqCst);
            live().retain(|(p, _)| *p != pid);
            let _ = tx.send(Msg::Exited);
        });

        // The run must say something within `startup`. After the process has exited, its pipes get `drain` to end: a job it
        // left behind may hold them, and stderr must be read to its end (or to that limit) BEFORE the failure is named,
        // since a classification can come from it.
        // A level that checks its tools holds what it says until Claude Code's `init` has passed the check, so a refused run shows
        // nothing. Other levels stream exactly as they always did.
        let checked = claude_code::init_tools(&run.turn.level).is_some();
        let mut stream = Stream::with_init_tools(claude_code::init_tools(&run.turn.level));
        let mut finish = None;
        let mut held: Vec<ChatChunk> = Vec::new();
        let mut shown = !checked;
        let (mut out_eof, mut err_eof, mut gone, mut spoke) = (false, false, false, false);
        let startup_end = tokio::time::Instant::now() + run.timings.startup;
        let mut drain_end = None;
        // Set at a refusal: the stop's own bound (interrupt, terminate, then the drain), within which the process must be gone.
        let mut refusal_end = None;
        while !(out_eof && err_eof && gone) {
            let limit = match (drain_end, refusal_end, spoke) {
                (Some(end), _, _) | (None, Some(end), _) => Some(end),
                (None, None, false) => Some(startup_end),
                (None, None, true) => None,
            };
            let next = match limit {
                Some(end) => tokio::time::timeout_at(end, rx.recv()).await,
                None => Ok(rx.recv().await),
            };
            match next {
                // After a refusal the run is only drained until it is gone: nothing more is read.
                Ok(Some(Msg::Line(_))) if refusal_end.is_some() => {}
                Ok(Some(Msg::Line(text))) => {
                    spoke = true;
                    let chunks = stream.consume(&text);
                    // A refusal is authoritative: the run is stopped here, and nothing this line or an earlier one held is shown.
                    // The error is returned once the process is gone (the turn gate is released with it), not before.
                    if stream.refused_tools() {
                        guard.stop();
                        refusal_end = Some(tokio::time::Instant::now() + run.timings.interrupt_grace + run.timings.terminate_grace + run.timings.drain);
                        continue;
                    }
                    shown |= chunks.iter().any(|c| matches!(c, ChatChunk::Engine(_)));
                    if shown {
                        show(held.drain(..).chain(chunks), &mut finish, sink);
                    } else {
                        held.extend(chunks);
                    }
                }
                Ok(Some(Msg::OutEof)) => out_eof = true,
                Ok(Some(Msg::ErrEof)) => err_eof = true,
                Ok(Some(Msg::Exited)) => {
                    gone = true;
                    drain_end = Some(tokio::time::Instant::now() + run.timings.drain);
                }
                Ok(None) => break,
                // A pipe stayed open after the process ended.
                Err(_) if gone || refusal_end.is_some() => break,
                // The run never said anything.
                Err(_) => {
                    guard.stop();
                    log::line("ai claude failure kind=timeout");
                    return Err(AiError::new(ErrorKind::Timeout));
                }
            }
        }

        // A run that never reached its `init` shows what it held, in order, now that it has ended. A refused run shows nothing.
        let refused = stream.refused_tools();
        if !refused {
            show(held.drain(..), &mut finish, sink);
        }
        let stderr_text = String::from_utf8_lossy(&errors.lock().unwrap()).to_string();
        let text = stream.text().to_string();
        match stream.failure(&stderr_text) {
            None => Ok(Aggregate { text, finish: finish.or(Some(Finish::Stop)), ..Aggregate::default() }),
            // What was said is kept, and marked as cut. A refusal is never cut: it is named, with nothing kept.
            Some(_) if !refused && !text.trim().is_empty() => Ok(Aggregate { text, error: Some(ErrorKind::Interrupted), ..Aggregate::default() }),
            Some(mut err) => {
                // Nothing to keep: a failed request. Steps already taken stay done, so no other model is asked.
                if err.kind == ErrorKind::Interrupted {
                    err.kind = ErrorKind::Server;
                }
                err.after_steps = stream.took_steps();
                log::line(format!("ai claude failure kind={} code={}", err.kind.as_str(), err.code.as_deref().unwrap_or("-")));
                Err(err)
            }
        }
    }
}

/// Sends chunks in order and keeps the finish reason the run ends with.
fn show(chunks: impl IntoIterator<Item = ChatChunk>, finish: &mut Option<Finish>, sink: &mut (dyn FnMut(ChatChunk) + Send)) {
    for chunk in chunks {
        if let ChatChunk::Finish(f) = &chunk {
            *finish = Some(*f);
        }
        sink(chunk);
    }
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;
    use crate::ai::claude_code::{Level, Platform, CRASHED, NEEDS_GIT, PLAN_LIMIT, SIGNED_OUT};
    use crate::ai::provider::{Message, Part};
    use crate::ai::testkit;

    const SID: &str = "11111111-1111-4111-8111-111111111111";
    const MARKER: &str = "ZZ-LEAK-MARKER-7391";

    fn request(text: &str) -> ChatRequest {
        ChatRequest {
            model: "sonnet".into(),
            system: String::new(),
            messages: vec![Message { role: Role::User, parts: vec![Part::Text(text.into())] }],
            tools: Vec::new(),
            response_format: None,
            max_tokens: 1,
        }
    }

    struct Sandbox {
        dir: testkit::TempDir,
        /// Held while the test's runs live (see `testkit::claude_runs_shared`).
        _runs: Box<dyn std::any::Any>,
    }

    impl Drop for Sandbox {
        /// A test that failed must not leave its fake running: kill what is still alive in the sandbox.
        fn drop(&mut self) {
            for pid in running_in(self.dir.path()) {
                unsafe { libc::kill(pid, libc::SIGKILL) };
            }
            for entry in std::fs::read_dir(self.dir.path()).into_iter().flatten().flatten() {
                if let Some(pid) = std::fs::read_to_string(entry.path()).ok().and_then(|t| t.trim().parse::<i32>().ok()).filter(|p| running(*p)) {
                    if matches!(entry.path().extension().and_then(|e| e.to_str()), Some("pid" | "child")) {
                        unsafe { libc::kill(pid, libc::SIGKILL) };
                    }
                }
            }
        }
    }

    impl Sandbox {
        fn new() -> Self {
            Sandbox { _runs: Box::new(testkit::claude_runs_shared()), dir: testkit::TempDir::new("claude-run") }
        }

        /// For a test that calls `stop_all`: no other test has a run while it does.
        fn alone() -> Self {
            Sandbox { _runs: Box::new(testkit::claude_runs_alone()), dir: testkit::TempDir::new("claude-run") }
        }

        fn file(&self, name: &str) -> String {
            self.dir.path().join(name).to_string_lossy().to_string()
        }

        fn folder(&self, name: &str) -> String {
            let path = self.dir.path().join(name);
            std::fs::create_dir_all(&path).unwrap();
            path.to_string_lossy().to_string()
        }

        /// The fake claude, run through whatever Python this machine has.
        fn run(&self, transcript: Option<&str>, level: Level, extra: &[(&str, &str)], log: &str) -> Run {
            let python = testkit::python();
            let mut leading: Vec<String> = python.get_args().map(|a| a.to_string_lossy().to_string()).collect();
            leading.push(testkit::fixtures_dir().join("claude-code/fake_claude.py").to_string_lossy().to_string());
            let mut env: Vec<(String, String)> = vec![
                ("PATH".into(), std::env::var("PATH").unwrap_or_default()),
                ("NM_FAKE_CLAUDE_LOG".into(), log.to_string()),
                ("CANARY".into(), "kept".into()),
                // What must never reach the run:
                ("ANTHROPIC_API_KEY".into(), "sk-ant-FAKE".into()),
                ("ANTHROPIC_AUTH_TOKEN".into(), "tok-FAKE".into()),
                ("CLAUDE_CODE_OAUTH_TOKEN".into(), "oauth-FAKE".into()),
                ("ANTHROPIC_PROFILE".into(), "work".into()),
                ("CLAUDE_CODE_USE_BEDROCK".into(), "1".into()),
            ];
            if let Some(t) = transcript {
                env.push(("NM_FAKE_CLAUDE_TRANSCRIPT".into(), testkit::fixtures_dir().join("claude-code/transcripts").join(t).to_string_lossy().to_string()));
            }
            env.extend(extra.iter().map(|(k, v)| (k.to_string(), v.to_string())));
            Run {
                executable: python.get_program().to_string_lossy().to_string(),
                leading_args: leading,
                turn: Turn { level, model: "sonnet".into(), session_id: SID.into(), resume: false, platform: Platform::Linux },
                chat_folder: self.folder("chat"),
                preamble: None,
                base_env: env,
                timings: Timings { startup: Duration::from_secs(20), interrupt_grace: Duration::from_secs(2), terminate_grace: Duration::from_secs(2), drain: Duration::from_secs(1) },
            }
        }
    }

    struct Outcome {
        chunks: Vec<ChatChunk>,
        result: Result<Aggregate, AiError>,
        calls: Vec<serde_json::Value>,
    }

    async fn collect(run: Run, text: &str, log: &str) -> Outcome {
        let provider = ClaudeCode::new(run);
        let mut chunks = Vec::new();
        let result = provider.stream(&request(text), &mut |c| chunks.push(c)).await;
        let calls = std::fs::read_to_string(log).unwrap_or_default().lines().filter_map(|l| serde_json::from_str(l).ok()).collect();
        Outcome { chunks, result, calls }
    }

    impl Outcome {
        fn turn(&self) -> &serde_json::Value {
            self.calls.iter().find(|c| c["argv"][0] == "-p").expect("one claude -p call")
        }

        fn steps(&self) -> Vec<String> {
            let mut out: Vec<(String, String)> = Vec::new();
            for c in &self.chunks {
                if let ChatChunk::Step(s) = c {
                    let row = (s.id.clone(), serde_json::to_value(s.state).unwrap().as_str().unwrap().to_string());
                    match out.iter_mut().find(|r| r.0 == s.id) {
                        Some(old) => *old = row,
                        None => out.push(row),
                    }
                }
            }
            out.into_iter().map(|(id, state)| format!("{id}:{state}")).collect()
        }
    }

    /// Whether a process is running. A zombie is dead: in a container PID 1 (here cargo) never reaps what is left to it,
    /// so `kill(pid, 0)` alone would call a process that has long exited alive.
    fn running(pid: i32) -> bool {
        if unsafe { libc::kill(pid, 0) } != 0 {
            return false;
        }
        #[cfg(target_os = "linux")]
        if let Ok(stat) = std::fs::read_to_string(format!("/proc/{pid}/stat")) {
            // "pid (name) S ...": the state follows the last closing parenthesis.
            return !matches!(stat.rsplit(')').next().and_then(|rest| rest.trim_start().chars().next()), Some('Z' | 'X'));
        }
        true
    }

    fn alive(pid_file: &str) -> bool {
        std::fs::read_to_string(pid_file).ok().and_then(|t| t.trim().parse::<i32>().ok()).is_some_and(running)
    }

    /// Live processes whose working directory is inside `dir` (found through /proc, so Linux only): the fake and what it
    /// started all run in the sandbox's chat folder, whether or not they got to write a pid file.
    fn running_in(dir: &Path) -> Vec<i32> {
        #[cfg(target_os = "linux")]
        {
            let pids = std::fs::read_dir("/proc").into_iter().flatten().flatten().filter_map(|e| e.file_name().to_str()?.parse::<i32>().ok());
            return pids.filter(|pid| std::fs::read_link(format!("/proc/{pid}/cwd")).is_ok_and(|cwd| cwd.starts_with(dir)) && running(*pid)).collect();
        }
        #[allow(unreachable_code)]
        {
            let _ = dir;
            Vec::new()
        }
    }

    async fn wait_until_gone(files: &[String], seconds: u64) -> bool {
        let end = std::time::Instant::now() + Duration::from_secs(seconds);
        while std::time::Instant::now() < end {
            if files.iter().all(|f| !alive(f)) {
                return true;
            }
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
        false
    }

    #[tokio::test]
    async fn a_turn() {
        let s = Sandbox::new();
        let log = s.file("turn.jsonl");
        let run = s.run(Some("success.jsonl"), Level::ChatOnly, &[], &log);
        let argv = claude_code::arguments(&run.turn);
        let chat = run.chat_folder.clone();
        let out = collect(run, "Hello", &log).await;
        let agg = out.result.as_ref().unwrap();
        assert_eq!(agg.text, "Bonjour Zoé, hello! 🐱");
        assert_eq!(agg.finish, Some(Finish::Stop));
        let turn = out.turn();
        let got: Vec<String> = turn["argv"].as_array().unwrap().iter().map(|a| a.as_str().unwrap().to_string()).collect();
        assert_eq!(got, argv, "the command line is the engine's");
        assert_eq!(std::fs::canonicalize(turn["cwd"].as_str().unwrap()).unwrap(), std::fs::canonicalize(&chat).unwrap(), "it runs in the chat folder");
        let env = turn["env"].as_object().unwrap();
        for gone in ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_PROFILE", "CLAUDE_CODE_USE_BEDROCK"] {
            assert!(!env.contains_key(gone), "{gone} outranks the plan login");
        }
        assert_eq!(env["CANARY"], "kept");
        assert!(env["PATH"].as_str().unwrap().starts_with("/opt/homebrew/bin:/usr/local/bin:"), "the child's PATH finds node-based installs");
        let stdin: serde_json::Value = serde_json::from_str(turn["stdin"].as_str().unwrap()).unwrap();
        assert_eq!(stdin["message"]["content"][0]["text"], "Hello", "the message goes in on stdin, and stdin was closed (the fake reads to its end)");
        assert!(out.chunks.iter().any(|c| matches!(c, ChatChunk::Engine(r) if r.model == "claude-sonnet-5-5")));

        let tools_log = s.file("tools.jsonl");
        let mut run = s.run(Some("tool-use.jsonl"), Level::ReadOnly(s.folder("project")), &[], &tools_log);
        run.turn.resume = true;
        let tools = collect(run, "Read it", &tools_log).await;
        assert_eq!(tools.steps(), ["toolu_01A:done", "toolu_01B:failed"], "steps arrive as rows that update");
        assert_eq!(tools.result.unwrap().text, "I'll read the README.\n\nIt says it is a tiny demo.");
        assert!(tools.calls[0]["argv"].as_array().unwrap().iter().any(|a| a == "--resume"), "a later turn resumes the session");
    }

    #[tokio::test]
    async fn failures() {
        let s = Sandbox::new();
        let run_with = |transcript: &str, exit: &str, stderr: &str, name: &str| {
            let log = s.file(&format!("f-{name}.jsonl"));
            (s.run(Some(transcript), Level::ChatOnly, &[("NM_FAKE_CLAUDE_EXIT", exit), ("NM_FAKE_CLAUDE_STDERR", stderr)], &log), log)
        };
        let (run, log) = run_with("signed-out.jsonl", "1", "", "so");
        assert_eq!(collect(run, "hi", &log).await.result.unwrap_err().code.as_deref(), Some(SIGNED_OUT));
        let (run, log) = run_with("plan-limit.jsonl", "1", "", "pl");
        let err = collect(run, "hi", &log).await.result.unwrap_err();
        assert_eq!((err.kind, err.code.as_deref(), err.resets_at), (ErrorKind::Billing, Some(PLAN_LIMIT), Some(1_791_301_500)));
        let (run, log) = run_with("offline.jsonl", "1", "", "off");
        assert_eq!(collect(run, "hi", &log).await.result.unwrap_err().code.as_deref(), Some(claude_code::OFFLINE));
        let (run, log) = run_with("crash.jsonl", "2", "", "cr");
        let crash = collect(run, "hi", &log).await.result.unwrap();
        assert_eq!((crash.text.as_str(), crash.error), ("Let me look", Some(ErrorKind::Interrupted)), "a cut stream keeps what was said, marked as cut");
        let (run, log) = run_with("empty.jsonl", "139", "", "none");
        let nothing = collect(run, "hi", &log).await.result.unwrap_err();
        assert_eq!((nothing.kind, nothing.code.as_deref()), (ErrorKind::Server, Some(CRASHED)), "a crash with nothing to keep is a failed request");
        let (run, log) = run_with("empty.jsonl", "1", "Claude Code on Windows requires git-bash", "git");
        assert_eq!(collect(run, "hi", &log).await.result.unwrap_err().code.as_deref(), Some(NEEDS_GIT));

        let mut missing = s.run(None, Level::ChatOnly, &[], &s.file("none.jsonl"));
        missing.executable = "/nonexistent/claude".into();
        missing.leading_args.clear();
        let err = collect(missing, "hi", &s.file("none.jsonl")).await.result.unwrap_err();
        assert_eq!((err.kind, err.code.as_deref()), (ErrorKind::Unreachable, Some(MISSING)), "no such program is 'not installed'");
        let gone = collect(s.run(Some("success.jsonl"), Level::ReadOnly("/nonexistent-folder-zz".into()), &[], &s.file("gone.jsonl")), "hi", &s.file("gone.jsonl")).await;
        assert_eq!(gone.result.unwrap_err().code.as_deref(), Some(FOLDER_MISSING));
        assert!(gone.calls.is_empty(), "and nothing was started");

        let mut quiet = s.run(None, Level::ChatOnly, &[("NM_FAKE_CLAUDE_HANG_AFTER", "0"), ("NM_FAKE_CLAUDE_PIDFILE", &s.file("quiet.pid"))], &s.file("quiet.jsonl"));
        quiet.timings = Timings { startup: Duration::from_millis(600), interrupt_grace: Duration::from_millis(200), terminate_grace: Duration::from_millis(200), drain: Duration::from_millis(200) };
        let silent = collect(quiet, "hi", &s.file("quiet.jsonl")).await;
        assert_eq!(silent.result.unwrap_err().kind, ErrorKind::Timeout, "a run that never says anything times out");
        assert!(wait_until_gone(&[s.file("quiet.pid")], 5).await, "and is stopped");
    }

    #[tokio::test]
    async fn stop_ends_the_process_and_what_it_started() {
        for stubborn in [false, true] {
            let s = Sandbox::new();
            let tag = if stubborn { "stubborn" } else { "polite" };
            let (pid, child) = (s.file(&format!("{tag}.pid")), s.file(&format!("{tag}.child")));
            let mut extra = vec![("NM_FAKE_CLAUDE_HANG_AFTER", "8"), ("NM_FAKE_CLAUDE_PIDFILE", pid.as_str()), ("NM_FAKE_CLAUDE_CHILD_PIDFILE", child.as_str())];
            if stubborn {
                extra.push(("NM_FAKE_CLAUDE_STUBBORN", "1"));
            }
            let log = s.file(&format!("{tag}.jsonl"));
            let mut run = s.run(Some("tool-use.jsonl"), Level::ChatOnly, &extra, &log);
            run.timings = Timings { startup: Duration::from_secs(20), interrupt_grace: Duration::from_millis(300), terminate_grace: Duration::from_millis(300), drain: Duration::from_millis(300) };
            let provider = ClaudeCode::new(run);
            let (seen_tx, seen_rx) = tokio::sync::oneshot::channel::<()>();
            let seen_tx = Mutex::new(Some(seen_tx));
            let req = request("go");
            let mut sink = |c: ChatChunk| {
                if matches!(c, ChatChunk::Step(_)) {
                    if let Some(tx) = seen_tx.lock().unwrap().take() {
                        let _ = tx.send(());
                    }
                }
            };
            // Stop: the future is dropped while a step is running, as `session::attempt` does. The fake writes the
            // pid of the child it started a moment after its step line: wait for it, so "gone" means something.
            let (pid_file, child_file) = (pid.clone(), child.clone());
            tokio::select! {
                _ = provider.stream(&req, &mut sink) => panic!("{tag}: the run was meant to hang"),
                _ = async {
                    let _ = seen_rx.await;
                    // The fake creates the file, then writes the pid: wait for a pid, not for the file.
                    let end = std::time::Instant::now() + Duration::from_secs(10);
                    while !alive(&child_file) && std::time::Instant::now() < end {
                        tokio::time::sleep(Duration::from_millis(20)).await;
                    }
                    assert!(alive(&pid_file) && alive(&child_file), "{tag}: both were running when Stop came");
                } => {}
            }
            assert!(wait_until_gone(&[pid, child], 8).await, "{tag}: the process and what it started are gone");
        }
    }

    /// The runs `quitting_stops_every_run_and_what_it_started` and its siblings start: hanging after the first step, each
    /// with a child, the stubborn ones deaf to the interrupt and the terminate.
    fn hanging(s: &Sandbox, tag: &str, stubborn: bool) -> (ClaudeCode, String, String) {
        let (pid, child) = (s.file(&format!("{tag}.pid")), s.file(&format!("{tag}.child")));
        let mut extra = vec![("NM_FAKE_CLAUDE_HANG_AFTER", "8"), ("NM_FAKE_CLAUDE_PIDFILE", pid.as_str()), ("NM_FAKE_CLAUDE_CHILD_PIDFILE", child.as_str())];
        if stubborn {
            extra.push(("NM_FAKE_CLAUDE_STUBBORN", "1"));
        }
        let mut run = s.run(Some("tool-use.jsonl"), Level::ChatOnly, &extra, &s.file(&format!("{tag}.jsonl")));
        run.timings = Timings { startup: Duration::from_secs(20), interrupt_grace: Duration::from_secs(30), terminate_grace: Duration::from_secs(30), drain: Duration::from_millis(300) };
        (ClaudeCode::new(run), pid, child)
    }

    /// Quit: two runs are mid-turn, one polite and one that ignores the interrupt, each with a child. `stop_all` returns in
    /// about a second and they are all gone. The runs' own Stop timings are 30 s: only `stop_all` can end them in time.
    #[tokio::test]
    async fn quitting_stops_every_run_and_what_it_started() {
        let s = Sandbox::alone();
        let (polite, polite_pid, polite_child) = hanging(&s, "polite", false);
        let (stubborn, stubborn_pid, stubborn_child) = hanging(&s, "stubborn", true);
        let all = vec![polite_pid.clone(), polite_child.clone(), stubborn_pid.clone(), stubborn_child.clone()];
        let (ra, rb) = (request("go"), request("go"));
        let (mut sa, mut sb) = (|_: ChatChunk| {}, |_: ChatChunk| {});
        let quit = async {
            // The fake writes a child's pid a moment after its step line: wait for all four.
            let end = std::time::Instant::now() + Duration::from_secs(10);
            while !all.iter().all(|f| alive(f)) && std::time::Instant::now() < end {
                tokio::time::sleep(Duration::from_millis(20)).await;
            }
            assert!(all.iter().all(|f| alive(f)), "both runs and both children were running when the app quit");
            assert_eq!(live_count(), 2, "both runs are in the registry");
            let start = std::time::Instant::now();
            stop_all();
            assert!(start.elapsed() < Duration::from_secs(3), "quit is bounded: {:?}", start.elapsed());
            assert!(wait_until_gone(&all, 4).await, "the runs and what they started are gone");
        };
        let _ = tokio::join!(polite.stream(&ra, &mut sa), stubborn.stream(&rb, &mut sb), quit);
        assert_eq!(live_count(), 0, "and nothing is left in the registry");
    }

    #[tokio::test]
    async fn quitting_with_nothing_running_does_nothing() {
        let _s = Sandbox::alone();
        assert_eq!(live_count(), 0);
        let start = std::time::Instant::now();
        stop_all();
        assert!(start.elapsed() < Duration::from_millis(200), "no wait when nothing runs");
        assert_eq!(live_count(), 0);
    }

    #[tokio::test]
    async fn a_run_that_finished_is_no_longer_in_the_registry() {
        let s = Sandbox::alone();
        let log = s.file("done.jsonl");
        let out = collect(s.run(Some("success.jsonl"), Level::ChatOnly, &[], &log), "hi", &log).await;
        assert!(out.result.is_ok());
        assert_eq!(live_count(), 0, "a run leaves the registry when its process exits");
        let log = s.file("failed.jsonl");
        let failed = collect(s.run(Some("signed-out.jsonl"), Level::ChatOnly, &[("NM_FAKE_CLAUDE_EXIT", "1")], &log), "hi", &log).await;
        assert!(failed.result.is_err());
        assert_eq!(live_count(), 0, "a run that failed too");
    }

    #[tokio::test]
    async fn two_runs_at_once_do_not_share_anything() {
        let s = Sandbox::new();
        let (a_log, b_log) = (s.file("a.jsonl"), s.file("b.jsonl"));
        let mut a = s.run(Some("success.jsonl"), Level::ChatOnly, &[], &a_log);
        a.turn.session_id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa".into();
        let mut b = s.run(Some("tool-use.jsonl"), Level::ReadOnly(s.folder("other")), &[], &b_log);
        b.turn.session_id = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb".into();
        let (one, two) = tokio::join!(collect(a, "hi", &a_log), collect(b, "hi", &b_log));
        assert_eq!(one.result.as_ref().unwrap().text, "Bonjour Zoé, hello! 🐱");
        assert_eq!(two.result.as_ref().unwrap().text, "I'll read the README.\n\nIt says it is a tiny demo.");
        let has = |o: &Outcome, id: &str| o.turn()["argv"].as_array().unwrap().iter().any(|a| a == id);
        assert!(has(&one, "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa") && has(&two, "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"), "each run has its own session");
        assert_eq!((one.steps().len(), two.steps().len()), (0, 2), "a chat's steps never reach the other");
    }

    #[tokio::test]
    async fn a_folder_with_spaces_and_non_ascii_characters() {
        let s = Sandbox::new();
        let folder = s.folder("Zoé Mes projets/ünï côde");
        let log = s.file("unicode.jsonl");
        let out = collect(s.run(Some("tool-use.jsonl"), Level::ReadOnly(folder.clone()), &[], &log), "hi", &log).await;
        assert!(out.result.as_ref().unwrap().text.ends_with("tiny demo."));
        assert_eq!(std::fs::canonicalize(out.turn()["cwd"].as_str().unwrap()).unwrap(), std::fs::canonicalize(&folder).unwrap());
        assert!(!out.turn()["argv"].as_array().unwrap().iter().any(|a| a.as_str().unwrap().contains("ünï")), "and no argument carries it");
    }

    #[tokio::test]
    async fn nothing_private_reaches_the_log() {
        let s = Sandbox::new();
        let folder = s.folder(&format!("{MARKER}-folder"));
        let log = s.file("leak.jsonl");
        for transcript in ["success.jsonl", "plan-limit.jsonl", "crash.jsonl"] {
            let run = s.run(Some(transcript), Level::ReadOnly(folder.clone()), &[("NM_FAKE_CLAUDE_STDERR", &format!("stderr says {MARKER}")), ("LEAK_ENV", MARKER), ("NM_FAKE_CLAUDE_EXIT", "1")], &log);
            let _ = collect(run, &format!("tell me about {MARKER}"), &log).await;
        }
        let lines = crate::log::CAPTURED.lock().unwrap().clone();
        assert!(lines.iter().any(|l| l.starts_with("ai claude failure")), "failures were logged");
        assert!(!lines.iter().any(|l| l.contains(MARKER)), "no log line holds the prompt, the folder, stderr or the environment");
        assert!(!lines.iter().any(|l| l.contains(SID)), "and none holds the session id");
    }

    /// Stop at any moment of the launch, and nothing is left running: the run is dropped before it is polled, while the
    /// process starts, and while the fake is still booting or already hanging with a child. Half the runs ignore the
    /// interrupt and the terminate, so only the kill ends them.
    #[tokio::test]
    async fn stop_at_any_moment_of_the_launch_leaves_nothing_running() {
        let s = Sandbox::new();
        let quick = Timings { startup: Duration::from_secs(20), interrupt_grace: Duration::from_millis(150), terminate_grace: Duration::from_millis(150), drain: Duration::from_millis(150) };
        let never = s.file("never.pid");
        let mut run = s.run(Some("tool-use.jsonl"), Level::ChatOnly, &[("NM_FAKE_CLAUDE_PIDFILE", never.as_str())], &s.file("never.jsonl"));
        run.timings = quick;
        {
            let provider = ClaudeCode::new(run);
            let (req, mut sink) = (request("go"), |_: ChatChunk| {});
            drop(provider.stream(&req, &mut sink));
        }
        tokio::time::sleep(Duration::from_millis(500)).await;
        assert!(!Path::new(&never).exists() && !Path::new(&s.file("never.jsonl")).exists(), "a turn that was never polled starts nothing");

        for i in 0..=20u64 {
            let (pid, child) = (s.file(&format!("r{i}.pid")), s.file(&format!("r{i}.child")));
            let mut extra = vec![("NM_FAKE_CLAUDE_HANG_AFTER", "1"), ("NM_FAKE_CLAUDE_PIDFILE", pid.as_str()), ("NM_FAKE_CLAUDE_CHILD_PIDFILE", child.as_str())];
            if i % 2 == 1 {
                extra.push(("NM_FAKE_CLAUDE_STUBBORN", "1"));
            }
            let mut run = s.run(Some("tool-use.jsonl"), Level::ChatOnly, &extra, &s.file(&format!("r{i}.jsonl")));
            run.timings = quick;
            let provider = ClaudeCode::new(run);
            let (req, mut sink) = (request("go"), |_: ChatChunk| {});
            tokio::select! {
                biased;
                _ = provider.stream(&req, &mut sink) => panic!("run {i}: meant to hang"),
                _ = tokio::time::sleep(Duration::from_millis(i * 10)) => {}
            }
        }
        let end = std::time::Instant::now() + Duration::from_secs(10);
        while std::time::Instant::now() < end && !running_in(s.dir.path()).is_empty() {
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
        assert_eq!(running_in(s.dir.path()), Vec::<i32>::new(), "no fake claude and no child of one outlives its Stop");
    }

    /// stderr arrives a moment after the process and stdout are gone: it is still read (for `drain`) before the failure is
    /// named, so a classification that comes from stderr does not depend on thread timing.
    #[tokio::test]
    async fn stderr_is_read_to_the_end_before_the_failure_is_named() {
        let s = Sandbox::new();
        let log = s.file("late.jsonl");
        let mut run = s.run(None, Level::ChatOnly, &[], &log);
        run.executable = "/bin/sh".into();
        run.leading_args = vec!["-c".into(), "exec 1>&-; (sleep 0.4; echo 'Claude Code on Windows requires git-bash' >&2) & exit 1".into(), "sh".into()];
        run.timings.drain = Duration::from_millis(2_000);
        let err = collect(run, "hi", &log).await.result.unwrap_err();
        assert_eq!(err.code.as_deref(), Some(NEEDS_GIT), "late stderr still counts");
    }

    /// A failure after Claude Code took steps says so, so Auto does not hand the question to another model.
    #[tokio::test]
    async fn a_failure_after_steps_says_so() {
        let s = Sandbox::new();
        let source = std::fs::read_to_string(testkit::fixtures_dir().join("claude-code/transcripts/tool-use.jsonl")).unwrap();
        let lines: Vec<&str> = source.lines().collect();
        // The init line and a tool started, no text and no result: the run is cut.
        let cut: Vec<&str> = std::iter::once(lines[0]).chain(lines[15..20].iter().copied()).collect();
        std::fs::write(s.file("cut.jsonl"), cut.join("\n") + "\n").unwrap();
        let log = s.file("steps.jsonl");
        let err = collect(s.run(Some(&s.file("cut.jsonl")), Level::ChatOnly, &[("NM_FAKE_CLAUDE_EXIT", "1")], &log), "hi", &log).await.result.unwrap_err();
        assert_eq!((err.kind, err.code.as_deref(), err.after_steps), (ErrorKind::Server, Some(CRASHED), true));
        let log = s.file("no-steps.jsonl");
        let err = collect(s.run(Some("signed-out.jsonl"), Level::ChatOnly, &[("NM_FAKE_CLAUDE_EXIT", "1")], &log), "hi", &log).await.result.unwrap_err();
        assert!(!err.after_steps, "no step was taken: another model may be asked");
    }

    /// The tools a run was started with: the value after its `--tools` flag.
    fn tools_of(call: &serde_json::Value) -> String {
        let argv = call["argv"].as_array().unwrap();
        let at = argv.iter().position(|a| a == "--tools").expect("a --tools flag");
        argv[at + 1].as_str().unwrap().to_string()
    }

    /// A no-tools run whose `init` names a tool: Claude Code's init says WebFetch, then it streams text. The run is stopped
    /// at the refusal, shows nothing, and nothing it started is left running.
    #[tokio::test]
    async fn a_refused_run_is_stopped_and_shows_nothing() {
        let s = Sandbox::new();
        let log = s.file("leaky.jsonl");
        let pid = s.file("leaky.pid");
        let run = s.run(Some("no-tools-leaky.jsonl"), Level::NoTools, &[("NM_FAKE_CLAUDE_HANG_AFTER", "2"), ("NM_FAKE_CLAUDE_PIDFILE", pid.as_str())], &log);
        // A regression that stops the run late or never must fail here, not hang the test run.
        let out = tokio::time::timeout(std::time::Duration::from_secs(20), collect(run, "hi", &log)).await.expect("a refused run ends within 20 s");
        let err = out.result.unwrap_err();
        assert_eq!(err.code.as_deref(), Some(claude_code::TOOLS_PRESENT), "the refusal is named: {err:?}");
        assert_eq!(err.kind, ErrorKind::BadRequest);
        assert!(!err.kind.is_temporary(), "so no local model answers a refused run");
        assert!(!out.chunks.iter().any(|c| matches!(c, ChatChunk::Engine(_))), "the refused init's engine report is not shown: {:?}", out.chunks);
        assert!(!out.chunks.iter().any(|c| matches!(c, ChatChunk::Text(_))), "nothing it says is shown: {:?}", out.chunks);
        assert!(!out.chunks.iter().any(|c| matches!(c, ChatChunk::Finish(_))), "and no finish either");
        // Gone BEFORE the error is returned: the turn gate is released with it, and a stop left to a detached thread would
        // leave the refused process alive behind a free gate.
        assert!(!alive(&pid), "the process is gone when the refusal is returned, not some time after");
    }

    /// The same no-tools level on a run that names no tool: the answer comes through, with the tools flags it was started with.
    #[tokio::test]
    async fn a_clean_no_tools_run_answers() {
        let s = Sandbox::new();
        let log = s.file("no-tools.jsonl");
        let run = s.run(Some("no-tools.jsonl"), Level::NoTools, &[], &log);
        let argv = claude_code::arguments(&run.turn);
        let out = collect(run, "fix this", &log).await;
        let agg = out.result.as_ref().unwrap();
        assert_eq!(agg.text, "Fixed text.");
        assert_eq!(agg.finish, Some(Finish::Stop));
        let got: Vec<String> = out.turn()["argv"].as_array().unwrap().iter().map(|a| a.as_str().unwrap().to_string()).collect();
        assert_eq!(got, argv, "the command line is the engine's");
        assert_eq!(tools_of(out.turn()), "", "no tool at all");
    }
}
