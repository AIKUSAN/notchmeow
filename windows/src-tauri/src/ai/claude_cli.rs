// Finding the user's Claude Code and asking it two questions: its version and whether it is signed in. These run when
// Settings opens and before a chat's first turn, never on a timer. NotchMeow never reads Claude Code's credential files
// or keychain items: it only reads `authMethod` out of `claude auth status` and keeps nothing else. The rules are in
// tests/fixtures/ai/claude-code/ (locator-cases.json, auth-status.json, versions.json). std::process only.

use std::collections::BTreeMap;
use std::ffi::OsString;
use std::io::Read;
use std::path::Path;
use std::process::{Child, Command, Stdio};
use std::sync::{mpsc, Arc, Mutex};
use std::time::{Duration, Instant};

use serde::Serialize;
use serde_json::Value;

use crate::ai::claude_code::{self, Platform};

/// The version the flags in expected-args.json were verified against (2026-10-06). One number to lower once older
/// versions have been checked.
pub const MINIMUM_VERSION: [u32; 3] = [2, 1, 211];

/// One variable of an environment. On Windows names compare without regard to case (the real `PATH` is usually spelled
/// `Path`): an exact match wins, else the first that matches in any case. Elsewhere the name is exact.
fn env_get<'a>(env: &'a BTreeMap<String, String>, name: &str, insensitive: bool) -> Option<&'a String> {
    env.get(name).or_else(|| if insensitive { env.iter().find(|(k, _)| k.eq_ignore_ascii_case(name)).map(|(_, v)| v) } else { None })
}

/// A folder name that marks Claude Desktop's own install, which can shadow Claude Code's `claude.exe` on `PATH`.
const DESKTOP_MARKERS: [&str; 2] = ["anthropicclaude", "windowsapps"];

// ── Where it is ─────────────────────────────────────────────────────────────────────────────────────────────────────

#[derive(Debug, Default, PartialEq, Eq)]
pub struct Found {
    pub path: Option<String>,
    /// Only a `claude.cmd` shim was found: it cannot take JSON arguments safely, so it is never run.
    pub shim_only: bool,
    pub asked_shell: bool,
}

/// The first place claude is, in order. macOS and Linux: ~/.local/bin/claude, /opt/homebrew/bin/claude,
/// /usr/local/bin/claude, ~/.npm-global/bin/claude, $NPM_CONFIG_PREFIX/bin/claude, then the login shell's `command -v
/// claude` (asked only when nothing earlier exists: starting a login shell is slow). Windows:
/// %USERPROFILE%\.local\bin\claude.exe first, then claude.exe on PATH unless it sits in a Claude Desktop folder.
pub fn find(
    platform: Platform,
    home: &str,
    env: &BTreeMap<String, String>,
    is_executable: impl Fn(&str) -> bool,
    login_shell: impl FnOnce() -> Option<String>,
) -> Found {
    if platform == Platform::Windows {
        let mut candidates = vec![format!("{home}\\.local\\bin\\claude.exe")];
        let mut shim = false;
        for dir in env_get(env, "PATH", true).map(String::as_str).unwrap_or("").split(';').filter(|d| !d.is_empty()) {
            let lower = dir.to_lowercase();
            if DESKTOP_MARKERS.iter().any(|m| lower.contains(m)) {
                continue;
            }
            let dir = dir.trim_end_matches('\\');
            candidates.push(format!("{dir}\\claude.exe"));
            shim = shim || is_executable(&format!("{dir}\\claude.cmd"));
        }
        return match candidates.into_iter().find(|c| is_executable(c)) {
            Some(path) => Found { path: Some(path), ..Found::default() },
            None => Found { shim_only: shim, ..Found::default() },
        };
    }
    let mut candidates = vec![
        format!("{home}/.local/bin/claude"),
        "/opt/homebrew/bin/claude".to_string(),
        "/usr/local/bin/claude".to_string(),
        format!("{home}/.npm-global/bin/claude"),
    ];
    if let Some(prefix) = env.get("NPM_CONFIG_PREFIX").filter(|p| !p.is_empty()) {
        candidates.push(format!("{}/bin/claude", prefix.trim_end_matches('/')));
    }
    if let Some(path) = candidates.into_iter().find(|c| is_executable(c)) {
        return Found { path: Some(path), ..Found::default() };
    }
    let printed = login_shell().unwrap_or_default();
    let last = printed.lines().map(str::trim).rfind(|l| !l.is_empty()).unwrap_or("");
    let path = (last.starts_with('/') && is_executable(last)).then(|| last.to_string());
    Found { path, shim_only: false, asked_shell: true }
}

#[cfg(unix)]
fn executable_on_disk(path: &str) -> bool {
    use std::os::unix::fs::PermissionsExt;
    std::fs::metadata(path).map(|m| m.is_file() && m.permissions().mode() & 0o111 != 0).unwrap_or(false)
}

#[cfg(windows)]
fn executable_on_disk(path: &str) -> bool {
    Path::new(path).is_file()
}

/// Where the program is on this computer. The login shell is asked last, on macOS and Linux only.
pub fn locate(env: &BTreeMap<String, String>) -> Option<String> {
    // Debug builds only: `NM_CLAUDE_CODE_PATH_OVERRIDE` runs a chat against the fake claude. Compiled out of release builds,
    // so a shipped app can't be pointed at another program.
    #[cfg(debug_assertions)]
    if let Some(path) = env.get("NM_CLAUDE_CODE_PATH_OVERRIDE").filter(|p| !p.is_empty()) {
        return Some(path.clone());
    }
    let home = crate::platform::home_dir().to_string_lossy().to_string();
    let platform = Platform::current();
    find(platform, &home, env, executable_on_disk, || login_shell_says(env)).path
}

/// `$SHELL -l -c 'command -v claude'`: a desktop-launched app has almost none of the user's PATH, their profile has it.
fn login_shell_says(env: &BTreeMap<String, String>) -> Option<String> {
    if cfg!(windows) {
        return None;
    }
    let shell = env.get("SHELL").filter(|s| s.starts_with('/')).cloned().unwrap_or_else(|| "/bin/sh".to_string());
    let (status, out) = run(&shell, &["-l".into(), "-c".into(), "command -v claude".into()], env, Duration::from_secs(5));
    status.map(|_| out)
}

// ── Its answers ─────────────────────────────────────────────────────────────────────────────────────────────────────

/// The first x.y.z in the output of `claude --version`.
pub fn parse_version(text: &str) -> Option<[u32; 3]> {
    text.split(|c: char| !(c.is_ascii_digit() || c == '.')).find_map(|token| {
        let mut parts = token.split('.').map(|p| p.parse::<u32>().ok());
        Some([parts.next()??, parts.next()??, parts.next()??])
    })
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VersionCheck {
    Ok,
    TooOld,
    Unknown,
}

pub fn check_version(version: Option<[u32; 3]>) -> VersionCheck {
    match version {
        None => VersionCheck::Unknown,
        Some(v) if v < MINIMUM_VERSION => VersionCheck::TooOld,
        Some(_) => VersionCheck::Ok,
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Auth {
    SignedIn(Option<String>),
    SignedOut,
    Unknown,
}

/// `claude auth status`: exit 0 signed in, 1 signed out. Only `authMethod` is read. `none` is signed out whatever the exit
/// status says. `exit` is `None` when the program could not be run.
pub fn parse_auth(exit: Option<i32>, stdout: &str) -> Auth {
    let Some(exit) = exit else { return Auth::Unknown };
    let method = serde_json::from_str::<Value>(stdout).ok().and_then(|v| v.get("authMethod").and_then(Value::as_str).map(str::to_string));
    if exit == 1 || method.as_deref() == Some("none") {
        return Auth::SignedOut;
    }
    if exit == 0 {
        Auth::SignedIn(method)
    } else {
        Auth::Unknown
    }
}

/// Where Claude Code on native Windows needs Git for Windows' bash: an environment variable, then the usual places.
pub fn git_bash_candidates(env: &BTreeMap<String, String>) -> Vec<String> {
    let mut list: Vec<String> = env_get(env, "CLAUDE_CODE_GIT_BASH_PATH", true).filter(|p| !p.is_empty()).cloned().into_iter().collect();
    for (var, tail) in [
        ("ProgramFiles", "\\Git\\bin\\bash.exe"),
        ("ProgramFiles(x86)", "\\Git\\bin\\bash.exe"),
        ("LOCALAPPDATA", "\\Programs\\Git\\bin\\bash.exe"),
    ] {
        if let Some(base) = env_get(env, var, true).filter(|b| !b.is_empty()) {
            list.push(format!("{}{tail}", base.trim_end_matches('\\')));
        }
    }
    list
}

// ── The check that starts processes ─────────────────────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum State {
    NotInstalled,
    TooOld,
    SignedOut,
    SignedIn,
    Unknown,
}

/// What the last check found. `signed_in` is the only state the router treats as ready.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Status {
    pub state: State,
    #[serde(skip)]
    pub executable: Option<String>,
    /// "2.1.211"
    pub version: Option<String>,
    /// What `claude auth status` reports (`claude.ai`, `api_key`, …): the sign-in method, never an account.
    pub auth_method: Option<String>,
    /// Only a `claude.cmd` shim is installed (Windows).
    pub shim_only: bool,
    /// Windows: Git for Windows' bash was not found, and Claude Code will refuse to start without it.
    pub needs_git: bool,
}

impl Status {
    pub fn not_installed() -> Self {
        Status { state: State::NotInstalled, executable: None, version: None, auth_method: None, shim_only: false, needs_git: false }
    }

    pub fn is_ready(&self) -> bool {
        self.state == State::SignedIn
    }
}

/// PATH for the child on macOS and Linux: the program's own folder (a node-based install finds its `node` beside it), then
/// Homebrew's and `/usr/local`'s, then the rest of the existing PATH. No repeats (the first place stays), no empty entries.
/// An app launched from the desktop has almost no PATH, and `#!/usr/bin/env node` then fails silently.
pub fn search_path(executable: &str, existing: Option<&str>) -> String {
    let own = Path::new(executable).parent().map(|p| p.to_string_lossy().into_owned()).unwrap_or_default();
    let mut seen = std::collections::HashSet::new();
    [own.as_str(), "/opt/homebrew/bin", "/usr/local/bin"]
        .into_iter()
        .chain(existing.unwrap_or("").split(':'))
        .filter(|d| !d.is_empty() && seen.insert(*d))
        .collect::<Vec<_>>()
        .join(":")
}

/// The environment of a run or a check: `claude_code::environment` (which strips what outranks the plan login) and, off
/// Windows, that PATH. Windows runs a native `claude.exe`: nothing is added there.
pub fn child_environment(base: impl IntoIterator<Item = (String, String)>, platform: Platform, executable: &str) -> Vec<(String, String)> {
    let mut env = claude_code::environment(base, platform);
    if platform != Platform::Windows {
        let path = search_path(executable, env.iter().find(|(k, _)| k == "PATH").map(|(_, v)| v.as_str()));
        env.retain(|(k, _)| k != "PATH");
        env.push(("PATH".into(), path));
    }
    env
}

/// The environment of a check: the same as a turn's, so the answer is what a chat would get.
fn clean(env: &BTreeMap<String, String>, exe: &str) -> BTreeMap<String, String> {
    child_environment(env.clone(), Platform::current(), exe).into_iter().collect()
}

/// Where it is, its version and whether it is signed in. Blocking: call it off the async threads.
pub fn status(env: &BTreeMap<String, String>) -> Status {
    let located = locate(env);
    let mut status = match located {
        Some(exe) => status_of(&exe, env),
        None => Status::not_installed(),
    };
    if cfg!(windows) {
        status.needs_git = !git_bash_candidates(env).iter().any(|p| Path::new(p).is_file());
        if status.state == State::NotInstalled {
            // A claude.cmd shim next to nothing else: say so rather than "not installed".
            let home = crate::platform::home_dir().to_string_lossy().to_string();
            status.shim_only = find(Platform::Windows, &home, env, |p| Path::new(p).is_file(), || None).shim_only;
        }
    }
    status
}

/// The same for a program that is already known.
pub fn status_of(exe: &str, env: &BTreeMap<String, String>) -> Status {
    let clean = clean(env, exe);
    let (_, version_out) = run(exe, &["--version".into()], &clean, Duration::from_secs(5));
    let (auth_exit, auth_out) = run(exe, &["auth".into(), "status".into()], &clean, Duration::from_secs(10));
    let Some(version) = parse_version(&version_out) else { return Status::not_installed() };
    let shown = version.iter().map(u32::to_string).collect::<Vec<_>>().join(".");
    let mut status = Status { state: State::Unknown, executable: Some(exe.to_string()), version: Some(shown), ..Status::not_installed() };
    if check_version(Some(version)) == VersionCheck::TooOld {
        status.state = State::TooOld;
        return status;
    }
    match parse_auth(auth_exit, &auth_out) {
        Auth::SignedIn(method) => {
            status.state = State::SignedIn;
            status.auth_method = method;
        }
        Auth::SignedOut => status.state = State::SignedOut,
        Auth::Unknown => status.state = State::Unknown,
    }
    status
}

/// The most output of a short program that is kept.
const OUTPUT_LIMIT: usize = 65_536;
/// A short program that is past its time is asked to end (SIGTERM); this is how long it has before it and everything it
/// started are killed.
#[cfg(unix)]
const TERMINATE_GRACE: Duration = Duration::from_millis(300);
/// How long the output may stay open after the program ended: a job it left behind can hold the pipe for ever.
const DRAIN: Duration = Duration::from_millis(500);

/// This process's environment as strings. A name or a value that is not Unicode is converted lossily: `std::env::vars()`
/// panics on one, and one odd variable must not take the app down.
pub fn current_environment() -> BTreeMap<String, String> {
    lossy_environment(std::env::vars_os())
}

fn lossy_environment(vars: impl IntoIterator<Item = (OsString, OsString)>) -> BTreeMap<String, String> {
    vars.into_iter().map(|(k, v)| (k.to_string_lossy().into_owned(), v.to_string_lossy().into_owned())).collect()
}

/// Windows: the process and everything it started, at once.
#[cfg(windows)]
pub(crate) fn taskkill_tree(pid: u32) {
    let mut cmd = Command::new("taskkill");
    cmd.args(["/PID", &pid.to_string(), "/T", "/F"]).stdout(Stdio::null()).stderr(Stdio::null());
    crate::platform::no_console(&mut cmd);
    if !cmd.status().is_ok_and(|status| status.success()) {
        crate::log::line("ai claude taskkill did not succeed");
    }
}

/// Ends a program that ran out of time, and what it started. Unix: the program was started as its own process group, so
/// the group is asked to end and then, whatever is left of it, killed. Windows: `taskkill /T /F`.
fn end_tree(child: &mut Child) {
    #[cfg(unix)]
    {
        let group = -(child.id() as i32);
        unsafe { libc::kill(group, libc::SIGTERM) };
        let end = Instant::now() + TERMINATE_GRACE;
        while Instant::now() < end && !matches!(child.try_wait(), Ok(Some(_))) {
            std::thread::sleep(Duration::from_millis(10));
        }
        // The program may have gone while a job it started ignores TERM: the group is killed either way. Once the program
        // has been reaped, `kill(group, 0)` says whether anything of the group is left (while one is, the number cannot
        // be given to another group).
        let reaped = matches!(child.try_wait(), Ok(Some(_)));
        if !reaped || unsafe { libc::kill(group, 0) } == 0 {
            unsafe { libc::kill(group, libc::SIGKILL) };
        }
    }
    #[cfg(windows)]
    taskkill_tree(child.id());
    let _ = child.kill();
    let _ = child.wait();
}

/// Runs a short program and returns its exit status and output, or a `None` status when it could not be run or took too
/// long (then it and what it started are ended). It always returns soon after the program does, even when a job the
/// program left behind keeps its output open. The output is only ever parsed, never logged.
pub fn run(exe: &str, args: &[String], env: &BTreeMap<String, String>, timeout: Duration) -> (Option<i32>, String) {
    let mut cmd = Command::new(exe);
    cmd.args(args).env_clear().envs(env).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::null());
    crate::platform::no_console(&mut cmd);
    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;
        cmd.process_group(0);
    }
    let Ok(mut child) = cmd.spawn() else { return (None, String::new()) };
    // Read on a thread, into a buffer this thread can read at any time: waiting for the pipe to end would wait for a job
    // that holds it, so the wait for the thread has a limit.
    let mut stdout = child.stdout.take().expect("piped");
    let out = Arc::new(Mutex::new(Vec::<u8>::new()));
    let (ended, ended_rx) = mpsc::channel::<()>();
    let sink = out.clone();
    std::thread::spawn(move || {
        let mut chunk = [0u8; 4096];
        while let Ok(n @ 1..) = stdout.read(&mut chunk) {
            let mut all = sink.lock().unwrap();
            let room = OUTPUT_LIMIT.saturating_sub(all.len());
            all.extend_from_slice(&chunk[..n.min(room)]);
            if n >= room {
                break;
            }
        }
        let _ = ended.send(());
    });
    let deadline = Instant::now() + timeout;
    let status = loop {
        match child.try_wait() {
            Ok(Some(s)) => break s.code(),
            Ok(None) if Instant::now() < deadline => std::thread::sleep(Duration::from_millis(10)),
            _ => {
                end_tree(&mut child);
                let _ = ended_rx.recv_timeout(DRAIN);
                return (None, String::new());
            }
        }
    };
    let _ = ended_rx.recv_timeout(DRAIN);
    let text = String::from_utf8_lossy(&out.lock().unwrap()).to_string();
    (status, text)
}

// ── Sign in ─────────────────────────────────────────────────────────────────────────────────────────────────────────

/// Single-quoted for any POSIX shell, whatever the path holds (spaces, quotes, accents).
#[cfg_attr(windows, allow(dead_code))] // used by the sign-in terminal of macOS and Linux
pub fn sh_quoted(path: &str) -> String {
    format!("'{}'", path.replace('\'', "'\\''"))
}

/// Single-quoted for PowerShell: a quote inside is doubled. PowerShell also reads the typographic single quotes
/// (U+2018, U+2019, U+201A, U+201B) as quotes, so each of them is doubled too (`C:\Users\O’Brien` would end the string).
#[cfg_attr(not(windows), allow(dead_code))] // used by the sign-in console of Windows
pub fn powershell_quoted(path: &str) -> String {
    let mut out = String::from("'");
    for c in path.chars() {
        out.push(c);
        if matches!(c, '\'' | '\u{2018}' | '\u{2019}' | '\u{201A}' | '\u{201B}') {
            out.push(c);
        }
    }
    out.push('\'');
    out
}

/// What a terminal runs for "Sign in": `claude auth login`, in Anthropic's own flow. NotchMeow never sees what is typed or
/// opened there.
pub fn sign_in_script(exe: &str) -> String {
    format!("echo 'Signing in. Your browser opens to finish.'; {} auth login; echo; echo 'You can close this window and go back to NotchMeow.'; read -r _", sh_quoted(exe))
}

/// The terminals tried on Linux, in order: (program, the arguments before the command to run).
#[cfg_attr(windows, allow(dead_code))]
const LINUX_TERMINALS: [(&str, &[&str]); 5] = [
    ("x-terminal-emulator", &["-e"]),
    ("gnome-terminal", &["--"]),
    ("konsole", &["-e"]),
    ("xfce4-terminal", &["-x"]),
    ("xterm", &["-e"]),
];

/// The command that opens a terminal running the sign-in, on Linux; `None` when no terminal is installed.
#[cfg_attr(windows, allow(dead_code))]
pub fn linux_terminal_command(exe: &str, on_path: impl Fn(&str) -> bool) -> Option<(String, Vec<String>)> {
    let (program, lead) = LINUX_TERMINALS.iter().find(|(p, _)| on_path(p))?;
    let mut args: Vec<String> = lead.iter().map(|a| a.to_string()).collect();
    args.extend(["sh".into(), "-c".into(), sign_in_script(exe)]);
    Some((program.to_string(), args))
}

/// Opens a terminal that runs `claude auth login`. `false` when it could not be opened.
pub fn open_sign_in(exe: &str) -> bool {
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        const CREATE_NEW_CONSOLE: u32 = 0x0000_0010;
        let script = format!("& {} auth login", powershell_quoted(exe));
        Command::new("powershell.exe").args(["-NoExit", "-Command", &script]).creation_flags(CREATE_NEW_CONSOLE).spawn().is_ok()
    }
    #[cfg(not(windows))]
    {
        let Some((program, args)) = linux_terminal_command(exe, |p| crate::platform::find_on_path(p).is_some()) else { return false };
        Command::new(program).args(args).spawn().is_ok()
    }
}

// ── The folder ──────────────────────────────────────────────────────────────────────────────────────────────────────

/// The folder to work in, from the system's own dialog. `None` when the user cancelled or no dialog is available (the
/// chat then asks for the path as text).
pub fn pick_folder() -> Option<String> {
    #[cfg(windows)]
    let output = {
        let script = "Add-Type -AssemblyName System.Windows.Forms; $d = New-Object System.Windows.Forms.FolderBrowserDialog; \
                      $d.Description = 'Choose the folder Claude may work in'; \
                      if ($d.ShowDialog() -eq 'OK') { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8; Write-Output $d.SelectedPath }";
        let mut cmd = Command::new("powershell.exe");
        cmd.args(["-NoProfile", "-STA", "-Command", script]);
        crate::platform::no_console(&mut cmd);
        cmd.output().ok()?
    };
    #[cfg(not(windows))]
    let output = {
        let attempts: [(&str, &[&str]); 2] = [
            ("zenity", &["--file-selection", "--directory", "--title=Choose the folder Claude may work in"]),
            ("kdialog", &["--getexistingdirectory", "."]),
        ];
        let (program, args) = attempts.iter().find(|(p, _)| crate::platform::find_on_path(p).is_some())?;
        Command::new(program).args(*args).output().ok()?
    };
    let chosen = String::from_utf8_lossy(&output.stdout).lines().next()?.trim().to_string();
    (output.status.success() && !chosen.is_empty()).then_some(chosen)
}

/// A folder the chat may work in: it exists and is a folder.
pub fn check_folder(path: &str) -> Result<String, String> {
    let trimmed = path.trim();
    if !trimmed.is_empty() && Path::new(trimmed).is_dir() {
        Ok(trimmed.to_string())
    } else {
        Err("That folder isn't there.".to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ai::testkit;

    fn strings(v: &Value) -> Vec<String> {
        v.as_array().unwrap().iter().map(|s| s.as_str().unwrap().to_string()).collect()
    }

    #[test]
    fn where_claude_is_looked_for() {
        let data = testkit::load_json("claude-code/locator-cases.json");
        let markers: Vec<String> = strings(&data["windowsDesktopMarkers"]);
        assert_eq!(DESKTOP_MARKERS.to_vec(), markers);
        for c in data["cases"].as_array().unwrap() {
            let existing: Vec<String> = strings(&c["executables"]);
            let env: BTreeMap<String, String> = c["env"].as_object().unwrap().iter().map(|(k, v)| (k.clone(), v.as_str().unwrap().to_string())).collect();
            let platform = if c["platform"] == "windows" { Platform::Windows } else { Platform::Linux };
            let found = find(platform, c["home"].as_str().unwrap(), &env, |p| existing.iter().any(|e| e == p), || c["loginShell"].as_str().map(str::to_string));
            let name = c["name"].as_str().unwrap();
            assert_eq!(found.path.as_deref(), c["expect"].as_str(), "{name}");
            assert_eq!(found.shim_only, c["shimOnly"].as_bool().unwrap(), "{name}: a shim is never run");
            if platform != Platform::Windows {
                assert_eq!(found.asked_shell, c["loginShellCalled"].as_bool().unwrap(), "{name}: the login shell is asked only when nothing earlier exists");
            }
        }
    }

    #[cfg(debug_assertions)]
    #[test]
    fn a_debug_build_can_be_pointed_at_the_fake() {
        let env: BTreeMap<String, String> = [("NM_CLAUDE_CODE_PATH_OVERRIDE".to_string(), "/x/fake_claude.py".to_string())].into();
        assert_eq!(locate(&env).as_deref(), Some("/x/fake_claude.py"));
    }

    #[test]
    fn versions() {
        let data = testkit::load_json("claude-code/versions.json");
        assert_eq!(MINIMUM_VERSION.to_vec(), data["minimum"].as_array().unwrap().iter().map(|n| n.as_u64().unwrap() as u32).collect::<Vec<_>>());
        for c in data["parse"].as_array().unwrap() {
            let want = c["expect"].as_array().map(|a| [a[0].as_u64().unwrap() as u32, a[1].as_u64().unwrap() as u32, a[2].as_u64().unwrap() as u32]);
            assert_eq!(parse_version(c["text"].as_str().unwrap()), want, "parse {}", c["text"]);
        }
        for c in data["check"].as_array().unwrap() {
            let version = c["version"].as_array().map(|a| [a[0].as_u64().unwrap() as u32, a[1].as_u64().unwrap() as u32, a[2].as_u64().unwrap() as u32]);
            let want = match c["expect"].as_str().unwrap() {
                "ok" => VersionCheck::Ok,
                "tooOld" => VersionCheck::TooOld,
                _ => VersionCheck::Unknown,
            };
            assert_eq!(check_version(version), want, "check {}", c["version"]);
        }
    }

    #[test]
    fn auth_status() {
        let data = testkit::load_json("claude-code/auth-status.json");
        for c in data["cases"].as_array().unwrap() {
            let got = parse_auth(c["exit"].as_i64().map(|e| e as i32), c["stdout"].as_str().unwrap());
            let e = &c["expect"];
            let want = match e["state"].as_str().unwrap() {
                "signedIn" => Auth::SignedIn(e["authMethod"].as_str().map(str::to_string)),
                "signedOut" => Auth::SignedOut,
                _ => Auth::Unknown,
            };
            assert_eq!(got, want, "{}", c["name"]);
        }
    }

    #[test]
    fn git_for_windows_is_looked_for_in_the_usual_places() {
        let env: BTreeMap<String, String> = [
            ("CLAUDE_CODE_GIT_BASH_PATH", "D:\\Tools\\Git\\bin\\bash.exe"),
            ("ProgramFiles", "C:\\Program Files\\"),
            ("ProgramFiles(x86)", "C:\\Program Files (x86)"),
            ("LOCALAPPDATA", "C:\\Users\\José\\AppData\\Local"),
        ]
        .into_iter()
        .map(|(k, v)| (k.to_string(), v.to_string()))
        .collect();
        assert_eq!(
            git_bash_candidates(&env),
            [
                "D:\\Tools\\Git\\bin\\bash.exe",
                "C:\\Program Files\\Git\\bin\\bash.exe",
                "C:\\Program Files (x86)\\Git\\bin\\bash.exe",
                "C:\\Users\\José\\AppData\\Local\\Programs\\Git\\bin\\bash.exe",
            ]
        );
        assert!(git_bash_candidates(&BTreeMap::new()).is_empty());
    }

    #[test]
    fn windows_names_are_looked_up_without_regard_to_case() {
        let env: BTreeMap<String, String> = [("Path", "C:\\Tools;C:\\Windows")].into_iter().map(|(k, v)| (k.to_string(), v.to_string())).collect();
        let only = |p: &str| p == "C:\\Tools\\claude.exe";
        let found = find(Platform::Windows, "C:\\Users\\José", &env, only, || None);
        assert_eq!(found.path.as_deref(), Some("C:\\Tools\\claude.exe"), "the real variable is `Path`");
        let exact: BTreeMap<String, String> = [("PATH", "C:\\Tools"), ("Path", "C:\\Other")].into_iter().map(|(k, v)| (k.to_string(), v.to_string())).collect();
        assert_eq!(find(Platform::Windows, "C:\\Users\\José", &exact, only, || None).path.as_deref(), Some("C:\\Tools\\claude.exe"));
        // Elsewhere the name is exact: `Path` is not `PATH`.
        let unix_env: BTreeMap<String, String> = [("Path".to_string(), "/x".to_string())].into();
        assert_eq!(env_get(&unix_env, "PATH", false), None);
        assert_eq!(env_get(&unix_env, "PATH", true).map(String::as_str), Some("/x"));

        let odd: BTreeMap<String, String> = [
            ("claude_code_git_bash_path", "D:\\Git\\bin\\bash.exe"),
            ("PROGRAMFILES", "C:\\Program Files"),
            ("programfiles(x86)", "C:\\Program Files (x86)"),
            ("LocalAppData", "C:\\Users\\José\\AppData\\Local"),
        ]
        .into_iter()
        .map(|(k, v)| (k.to_string(), v.to_string()))
        .collect();
        assert_eq!(
            git_bash_candidates(&odd),
            [
                "D:\\Git\\bin\\bash.exe",
                "C:\\Program Files\\Git\\bin\\bash.exe",
                "C:\\Program Files (x86)\\Git\\bin\\bash.exe",
                "C:\\Users\\José\\AppData\\Local\\Programs\\Git\\bin\\bash.exe",
            ]
        );
    }

    #[test]
    fn powershell_reads_typographic_single_quotes_as_quotes() {
        for quote in ['\u{2018}', '\u{2019}', '\u{201A}', '\u{201B}'] {
            assert_eq!(powershell_quoted(&format!("C:\\Users\\O{quote}Brien\\claude.exe")), format!("'C:\\Users\\O{quote}{quote}Brien\\claude.exe'"), "U+{:04X}", quote as u32);
        }
        assert_eq!(powershell_quoted("C:\\Users\\Zoé Ünï O\u{2019}Neil's\\claude.exe"), "'C:\\Users\\Zoé Ünï O\u{2019}\u{2019}Neil''s\\claude.exe'");
    }

    #[test]
    fn quoting_for_a_shell_and_for_powershell() {
        assert_eq!(sh_quoted("/Users/O'Brien/Zoé Ünï/.local/bin/claude"), "'/Users/O'\\''Brien/Zoé Ünï/.local/bin/claude'");
        assert_eq!(powershell_quoted("C:\\Users\\José O'Neil\\claude.exe"), "'C:\\Users\\José O''Neil\\claude.exe'");
    }

    #[test]
    fn the_linux_terminal_is_the_first_one_installed() {
        let (program, args) = linux_terminal_command("/home/zoe/.local/bin/claude", |p| p == "konsole" || p == "xterm").unwrap();
        assert_eq!((program.as_str(), args[0].as_str(), args[1].as_str()), ("konsole", "-e", "sh"));
        assert!(args[3].contains("'/home/zoe/.local/bin/claude' auth login"));
        assert!(linux_terminal_command("/x/claude", |_| false).is_none(), "no terminal installed");
    }

    #[test]
    fn the_child_searches_its_own_folder_then_homebrew_then_the_rest() {
        assert_eq!(search_path("/home/zoe/.npm-global/bin/claude", Some("/usr/bin:/bin")), "/home/zoe/.npm-global/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin");
        assert_eq!(search_path("/home/zoe/.npm-global/bin/claude", None), "/home/zoe/.npm-global/bin:/opt/homebrew/bin:/usr/local/bin", "no PATH at all");
        assert_eq!(search_path("/usr/local/bin/claude", Some("/bin:/usr/local/bin:/usr/bin:/bin")), "/usr/local/bin:/opt/homebrew/bin:/bin:/usr/bin", "each folder once, the first place kept");
        assert_eq!(search_path("/x/claude", Some(":/usr/bin::/bin:")), "/x:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", "no empty entries");
        assert_eq!(search_path("claude", Some("/usr/bin")), "/opt/homebrew/bin:/usr/local/bin:/usr/bin", "a bare name has no folder of its own");
        assert_eq!(search_path("/Users/Zoé Mes outils/bin/claude", Some("/usr/bin")), "/Users/Zoé Mes outils/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin", "spaces are kept as they are");
    }

    #[test]
    fn the_childs_environment_keeps_the_login_rules_and_gets_the_path() {
        let base = [("PATH", "/usr/bin:/bin"), ("HOME", "/h"), ("ANTHROPIC_API_KEY", "sk-FAKE"), ("CLAUDE_CODE_OAUTH_TOKEN", "t")].map(|(k, v)| (k.to_string(), v.to_string()));
        let env: BTreeMap<String, String> = child_environment(base.clone(), Platform::Linux, "/h/.npm-global/bin/claude").into_iter().collect();
        assert_eq!(env["PATH"], "/h/.npm-global/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin");
        assert_eq!(env["HOME"], "/h");
        assert!(!env.contains_key("ANTHROPIC_API_KEY") && !env.contains_key("CLAUDE_CODE_OAUTH_TOKEN"), "what outranks the plan login stays stripped");
        let no_path: BTreeMap<String, String> = child_environment([("HOME".to_string(), "/h".to_string())], Platform::Linux, "/x/claude").into_iter().collect();
        assert_eq!(no_path["PATH"], "/x:/opt/homebrew/bin:/usr/local/bin", "a missing PATH is made");
        // Windows runs a native claude.exe: nothing is added.
        let win: BTreeMap<String, String> = child_environment([("Path".to_string(), "C:\\Windows".to_string())], Platform::Windows, "C:\\x\\claude.exe").into_iter().collect();
        assert_eq!(win, [("Path".to_string(), "C:\\Windows".to_string())].into());
    }

    /// A node-based install (`#!/usr/bin/env node`) started by an app that was launched from the desktop, which has almost no
    /// PATH: its `node` is beside it, in the folder the child now searches first. Stand-ins only: the real claude and node
    /// of this computer are never run.
    #[cfg(unix)]
    #[test]
    fn a_node_based_install_is_found_working_from_a_nearly_empty_path() {
        use std::os::unix::fs::PermissionsExt;
        let dir = testkit::TempDir::new("node-install");
        let bin = dir.path().join("Zoé npm global/bin");
        std::fs::create_dir_all(&bin).unwrap();
        for (name, body) in [("claude", "#!/usr/bin/env node\nconsole.log('never run as node');\n"), ("node", "#!/bin/sh\necho '2.1.300 (Claude Code)'\n")] {
            std::fs::write(bin.join(name), body).unwrap();
            std::fs::set_permissions(bin.join(name), std::fs::Permissions::from_mode(0o755)).unwrap();
        }
        let env: BTreeMap<String, String> = [("PATH".to_string(), "/usr/bin:/bin".to_string())].into();
        let found = status_of(&bin.join("claude").to_string_lossy(), &env);
        assert_eq!((found.version.as_deref(), found.state), (Some("2.1.300"), State::SignedIn), "{found:?}");
    }

    #[test]
    fn a_folder_the_chat_may_work_in() {
        let dir = testkit::TempDir::new("folder");
        assert_eq!(check_folder(&format!("  {}  ", dir.path().display())).unwrap(), dir.path().display().to_string());
        assert!(check_folder("").is_err() && check_folder(&dir.path().join("nope").display().to_string()).is_err());
    }

    /// The checks against the fake `claude`. Unix only: a script cannot be run as a program on Windows.
    #[cfg(unix)]
    #[test]
    fn the_checks_against_the_fake_claude() {
        let dir = testkit::TempDir::new("cli");
        let fake = dir.path().join("claude");
        // A link, not a copy: a file written by this process can be "text file busy" for an `exec` while another test
        // forks, which would make the program look not installed.
        std::os::unix::fs::symlink(testkit::fixtures_dir().join("claude-code/fake_claude.py"), &fake).unwrap();
        let env_with = |extra: &[(&str, &str)]| -> BTreeMap<String, String> {
            let mut env: BTreeMap<String, String> = current_environment().into_iter().filter(|(k, _)| k == "PATH").collect();
            env.insert("ANTHROPIC_API_KEY".into(), "sk-ant-FAKE".into());
            env.extend(extra.iter().map(|(k, v)| (k.to_string(), v.to_string())));
            env
        };
        let exe = fake.to_string_lossy().to_string();
        let ok = status_of(&exe, &env_with(&[]));
        assert_eq!((ok.state, ok.auth_method.as_deref(), ok.version.as_deref()), (State::SignedIn, Some("claude.ai"), Some("2.1.211")));
        let out = status_of(&exe, &env_with(&[("NM_FAKE_CLAUDE_AUTH_EXIT", "1"), ("NM_FAKE_CLAUDE_AUTH_JSON", "{\"authMethod\":\"none\"}")]));
        assert_eq!(out.state, State::SignedOut);
        assert_eq!(status_of(&exe, &env_with(&[("NM_FAKE_CLAUDE_VERSION", "2.1.100 (Claude Code)")])).state, State::TooOld);
        assert_eq!(status_of(&exe, &env_with(&[("NM_FAKE_CLAUDE_VERSION", "hello")])).state, State::NotInstalled);
        assert_eq!(status_of("/nonexistent/claude", &env_with(&[])).state, State::NotInstalled);
    }

    /// A variable that is not Unicode must not take the app down (`std::env::vars()` panics on it).
    #[cfg(unix)]
    #[test]
    fn an_environment_variable_that_is_not_unicode_is_kept_lossily() {
        use std::os::unix::ffi::OsStringExt;
        let odd = lossy_environment([
            (OsString::from("PATH"), OsString::from("/usr/bin")),
            (OsString::from_vec(b"ODD_VALUE".to_vec()), OsString::from_vec(b"caf\xe9".to_vec())),
            (OsString::from_vec(b"ODD_\xff_NAME".to_vec()), OsString::from("x")),
        ]);
        assert_eq!(odd["PATH"], "/usr/bin");
        assert_eq!(odd["ODD_VALUE"], "caf\u{fffd}");
        assert_eq!(odd["ODD_\u{fffd}_NAME"], "x");
        assert!(current_environment().contains_key("PATH"), "and the real environment is read the same way");
    }

    // ── The short runs: a hang must fail the test, never block it ─────────────────────────────────────────────────────

    #[cfg(unix)]
    fn running(pid: i32) -> bool {
        if unsafe { libc::kill(pid, 0) } != 0 {
            return false;
        }
        #[cfg(target_os = "linux")]
        if let Ok(stat) = std::fs::read_to_string(format!("/proc/{pid}/stat")) {
            // A zombie is dead: in a container PID 1 never reaps what is left to it.
            return !matches!(stat.rsplit(')').next().and_then(|rest| rest.trim_start().chars().next()), Some('Z' | 'X'));
        }
        true
    }

    #[cfg(unix)]
    fn pid_in(dir: &Path, name: &str) -> Option<i32> {
        std::fs::read_to_string(dir.join(name)).ok()?.trim().parse().ok()
    }

    /// Kills what a test left behind, on drop, so a test that failed leaves nothing running.
    #[cfg(unix)]
    struct KillLeftovers<'a>(&'a Path);

    #[cfg(unix)]
    impl Drop for KillLeftovers<'_> {
        fn drop(&mut self) {
            for name in ["sh.pid", "sleep.pid"] {
                if let Some(pid) = pid_in(self.0, name) {
                    unsafe { libc::kill(pid, libc::SIGKILL) };
                }
            }
        }
    }

    /// Runs `f` on a thread and gives up after `seconds`.
    #[cfg(unix)]
    fn within<T: Send + 'static>(seconds: u64, f: impl FnOnce() -> T + Send + 'static) -> Option<T> {
        let (tx, rx) = std::sync::mpsc::channel();
        std::thread::spawn(move || {
            let _ = tx.send(f());
        });
        rx.recv_timeout(Duration::from_secs(seconds)).ok()
    }

    #[cfg(unix)]
    fn path_env() -> BTreeMap<String, String> {
        [("PATH".to_string(), std::env::var_os("PATH").unwrap_or_default().to_string_lossy().to_string())].into()
    }

    #[cfg(unix)]
    fn wait_gone(dir: &Path, names: &[&str]) -> bool {
        let end = Instant::now() + Duration::from_secs(5);
        while Instant::now() < end {
            if names.iter().all(|n| pid_in(dir, n).is_some_and(|p| !running(p))) {
                return true;
            }
            std::thread::sleep(Duration::from_millis(20));
        }
        false
    }

    #[cfg(unix)]
    #[test]
    fn a_check_that_ignores_terminate_is_ended_and_run_returns() {
        let dir = testkit::TempDir::new("term");
        let _clean = KillLeftovers(dir.path());
        let script = format!("trap '' TERM; sleep 600 & echo $! > '{}/sleep.pid'; echo $$ > '{}/sh.pid'; while :; do sleep 1; done", dir.path().display(), dir.path().display());
        let started = Instant::now();
        let env = path_env();
        let got = within(20, move || run("/bin/sh", &["-c".into(), script], &env, Duration::from_millis(1_000))).expect("run came back instead of hanging");
        assert_eq!(got, (None, String::new()), "a check that did not finish has no status");
        assert!(started.elapsed() < Duration::from_secs(6), "within the timeout and a short grace, not {:?}", started.elapsed());
        assert!(wait_gone(dir.path(), &["sh.pid", "sleep.pid"]), "the program that ignores TERM and what it started are gone");
    }

    #[cfg(unix)]
    #[test]
    fn a_background_job_holding_the_output_does_not_hold_run() {
        let dir = testkit::TempDir::new("held");
        let _clean = KillLeftovers(dir.path());
        let script = format!("sleep 600 & echo $! > '{}/sleep.pid'; echo hello", dir.path().display());
        let started = Instant::now();
        let env = path_env();
        let got = within(20, move || run("/bin/sh", &["-c".into(), script], &env, Duration::from_secs(30))).expect("run came back instead of waiting for the job");
        assert_eq!(got, (Some(0), "hello\n".to_string()));
        assert!(started.elapsed() < Duration::from_secs(5), "it does not wait for a job that outlives the program: {:?}", started.elapsed());
    }

    #[cfg(unix)]
    #[test]
    fn run_returns_the_status_and_the_output() {
        let got = run("/bin/sh", &["-c".into(), "echo out; exit 3".into()], &path_env(), Duration::from_secs(5));
        assert_eq!(got, (Some(3), "out\n".to_string()));
        assert_eq!(run("/nonexistent/claude", &[], &path_env(), Duration::from_secs(5)), (None, String::new()));
    }
}
