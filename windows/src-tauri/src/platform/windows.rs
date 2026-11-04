// Windows: Win32 for the island window and the cursor, %APPDATA% for files.

mod drag;
mod share;

use std::os::windows::process::CommandExt;
use std::path::PathBuf;
use std::process::Command;

use tauri::{AppHandle, Manager, WebviewWindow};

use ::windows::core::{BOOL, PWSTR};
use ::windows::Win32::Foundation::{CloseHandle, HANDLE, HLOCAL, HWND, LPARAM, LocalFree, POINT, RECT};
use ::windows::Win32::Security::Authorization::ConvertSidToStringSidW;
use ::windows::Win32::Security::{GetTokenInformation, TokenUser, TOKEN_QUERY, TOKEN_USER};
use ::windows::Win32::System::Ole::RevokeDragDrop;
use ::windows::Win32::System::SystemInformation::GetLocalTime;
use ::windows::Win32::System::Threading::{GetCurrentProcess, OpenProcess, OpenProcessToken, QueryFullProcessImageNameW, PROCESS_NAME_WIN32, PROCESS_QUERY_LIMITED_INFORMATION};
use ::windows::Win32::UI::Input::KeyboardAndMouse::{GetAsyncKeyState, VK_LBUTTON, VK_MBUTTON, VK_RBUTTON};
use ::windows::Win32::UI::WindowsAndMessaging::{
    EnumChildWindows, GetAncestor, GetClassNameW, GetCursorPos, GetForegroundWindow, GetWindowLongPtrW, GetWindowRect, GetWindowThreadProcessId, SetWindowLongPtrW, WindowFromPoint,
    GA_ROOT, GWL_EXSTYLE, GWL_STYLE, WS_EX_NOACTIVATE, WS_EX_TOOLWINDOW,
};

use super::{DragDone, LocalTime};
use crate::desktop::{display_away, AwaySource};
use crate::island::WINDOW_LABEL;
use crate::sidekick_presence::{session_locked_from_flags, unlock_is_real};

/// File name of the Claude Code relay.
pub const HOOK_EXE: &str = "notchmeow-hook.exe";

/// Environment variable holding the home directory.
pub const HOME_VAR: &str = "USERPROFILE";

/// Keeps spawned helpers from flashing a console window.
const CREATE_NO_WINDOW: u32 = 0x0800_0000;

// ── Files ─────────────────────────────────────────────────────────────────────

/// %APPDATA%\NotchMeow — preferences.
pub fn config_dir() -> PathBuf {
    let base = std::env::var_os("APPDATA")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."));
    base.join("NotchMeow")
}

/// %LOCALAPPDATA%\NotchMeow — where notchmeow-hook.exe, the inbox and the log live.
pub fn local_dir() -> PathBuf {
    let base = std::env::var_os("LOCALAPPDATA")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."));
    base.join("NotchMeow")
}

/// %APPDATA% and %LOCALAPPDATA% are already private to the user.
pub fn ensure_private_dir(dir: &std::path::Path) -> std::io::Result<()> {
    std::fs::create_dir_all(dir)
}

/// Nothing to set up before the webview starts.
pub fn prepare_environment() {}

pub fn local_time() -> LocalTime {
    let t = unsafe { GetLocalTime() };
    LocalTime {
        year: t.wYear.into(),
        month: t.wMonth.into(),
        day: t.wDay.into(),
        hour: t.wHour.into(),
        minute: t.wMinute.into(),
        second: t.wSecond.into(),
    }
}

// ── Processes ─────────────────────────────────────────────────────────────────

/// Spawned helpers must never flash a console window.
pub fn no_console(cmd: &mut Command) -> &mut Command {
    cmd.creation_flags(CREATE_NO_WINDOW)
}

pub fn open_url(url: &str) {
    let _ = no_console(Command::new("rundll32.exe").args(["url.dll,FileProtocolHandler", url]))
        .spawn();
}

/// The Claude desktop app can be started (the pill's Open).
pub const CLAUDE_APP: bool = true;

/// Starts the Claude desktop app, or brings it forward when it runs (the app's own single-instance handling does that). The choice of what to start is `claude_app::pick`: the classic
/// install's paths and its Start-menu shortcut, else the packaged app the Start menu lists by name. Started through the shell with the path or the validated AUMID as ONE argument; no `cmd`.
pub fn open_claude_app() -> bool {
    let dir = |name: &str| std::env::var_os(name).map(PathBuf::from);
    let (local, roaming, programs) = (dir("LOCALAPPDATA"), dir("APPDATA"), dir("ProgramFiles"));
    let places = crate::claude_app::candidates(local.as_deref(), roaming.as_deref(), programs.as_deref());
    let launch = crate::claude_app::pick(&places, |p| p.is_file(), || {
        let out = no_console(Command::new("powershell.exe").args([
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            r#"Get-StartApps | ForEach-Object { $_.Name + "`t" + $_.AppID }"#,
        ]))
        .output()
        .ok()?;
        out.status.success().then(|| String::from_utf8_lossy(&out.stdout).into_owned())
    });
    match launch {
        Some(crate::claude_app::Launch::Path(path)) => no_console(Command::new("explorer.exe").arg(path)).spawn().is_ok(),
        Some(crate::claude_app::Launch::Aumid(id)) => no_console(Command::new("explorer.exe").arg(format!("shell:AppsFolder\\{id}"))).spawn().is_ok(),
        None => false,
    }
}

/// Drags these files out of the island with OLE (windows/drag.rs). Modal: returns when the button is released, so it runs on the main thread (dragout.rs).
pub fn drag_out(_win: &WebviewWindow, paths: Vec<PathBuf>, done: DragDone) {
    done(drag::run(&paths));
}

/// Windows has a system Share window (platform/windows/share.rs).
pub const SHARE: bool = true;

/// Opens the system's Share window over the island with these files. Called from a worker thread: it resolves the files there, then shows the window on the main thread, with the
/// island's window made activatable for the moment (the Share window needs a foreground owner, and the island is a window that never takes focus).
pub fn share_files(win: &WebviewWindow, paths: &[PathBuf]) -> Result<(), String> {
    let items = share::prepare(paths)?;
    let raw = hwnd_of(win).ok_or_else(|| "The island window is not there.".to_string())?.0 as isize;
    let target = win.clone();
    let (tx, rx) = std::sync::mpsc::channel();
    win.run_on_main_thread(move || {
        set_activating(&target, true);
        let _ = target.set_focus();
        let shown = share::show(HWND(raw as *mut _), items);
        set_activating(&target, false);
        let _ = tx.send(shown);
    })
    .map_err(|e| e.to_string())?;
    rx.recv().map_err(|e| e.to_string())?
}

/// Show in Explorer: the folder opens with the file selected. `raw_arg`, because Explorer reads `/select,"C:\a b\c.txt"` with its own rules and Rust's quoting would add a second pair.
pub fn reveal_file(path: &std::path::Path) {
    let _ = Command::new("explorer").raw_arg(format!("/select,\"{}\"", path.display())).spawn();
}

pub fn reveal_folder(path: &str) {
    let _ = Command::new("explorer").arg(path).spawn();
}

/// Our own `where`: walks %PATH% against %PATHEXT%, no shell involved.
/// Rust quotes arguments correctly for `.cmd`/`.bat` targets since 1.77, so
/// spawning `code.cmd` directly is safe.
pub fn find_on_path(stem: &str) -> Option<PathBuf> {
    let exts = std::env::var("PATHEXT").unwrap_or_else(|_| ".COM;.EXE;.BAT;.CMD".into());
    let dirs = std::env::var_os("PATH")?;
    for dir in std::env::split_paths(&dirs) {
        for ext in exts.split(';').filter(|e| !e.is_empty()) {
            let candidate = dir.join(format!("{stem}{}", ext.to_lowercase()));
            if candidate.is_file() {
                return Some(candidate);
            }
        }
    }
    None
}

// ── Who we are ────────────────────────────────────────────────────────────────
//
// Named pipes share one machine-wide namespace, so the SID in the name is what
// keeps two accounts on the same machine from ever meeting on `notchmeow-*`.
// notchmeow-hook computes the same string (hook/src/win.rs) and additionally checks
// that the process serving the pipe really is us.

/// The SID of the account this process runs as, as `S-1-5-21-…`.
pub fn current_user_sid() -> Option<String> {
    unsafe {
        let mut token = HANDLE::default();
        OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &mut token).ok()?;

        // First call sizes the buffer, second fills it.
        let mut needed = 0u32;
        let _ = GetTokenInformation(token, TokenUser, None, 0, &mut needed);
        if needed == 0 {
            let _ = CloseHandle(token);
            return None;
        }
        let mut buf = vec![0u8; needed as usize];
        let ok = GetTokenInformation(
            token,
            TokenUser,
            Some(buf.as_mut_ptr().cast()),
            needed,
            &mut needed,
        )
        .is_ok();
        let _ = CloseHandle(token);
        if !ok {
            return None;
        }

        let user = &*(buf.as_ptr() as *const TOKEN_USER);
        let mut text = PWSTR::null();
        ConvertSidToStringSidW(user.User.Sid, &mut text).ok()?;
        let sid = text.to_string().ok();
        let _ = LocalFree(Some(HLOCAL(text.0 as *mut _)));
        sid
    }
}

// ── Cursor ────────────────────────────────────────────────────────────────────

/// The 60 Hz poll reads the cursor and flips click-through from it.
pub const CURSOR_POLL: bool = true;

/// Cursor position in physical screen pixels.
pub fn cursor_physical() -> Option<(f64, f64)> {
    let mut p = POINT::default();
    unsafe { GetCursorPos(&mut p).ok()? };
    Some((p.x as f64, p.y as f64))
}

/// True while the left mouse button is held — the only signal we get that a
/// drag might be in flight before it reaches the window.
pub fn left_button_down() -> bool {
    unsafe { (GetAsyncKeyState(VK_LBUTTON.0 as i32) as u16 & 0x8000) != 0 }
}

/// The OS gives this app the pointer anywhere on screen (the island's poll reads it).
pub fn pointer_feed() -> bool {
    true
}

/// True while any mouse button is held. All three are watched, so swapped buttons (Settings → Mouse) make no difference.
pub fn any_button_down() -> bool {
    [VK_LBUTTON, VK_RBUTTON, VK_MBUTTON].iter().any(|k| unsafe { (GetAsyncKeyState(k.0 as i32) as u16 & 0x8000) != 0 })
}

/// Whether the window under the point (physical screen px) belongs to this app: the island, Settings, the desktop cat, the tray's menu. A click there is not outside the island.
pub fn press_is_own(_app: &AppHandle, x: f64, y: f64) -> bool {
    unsafe {
        let hwnd = WindowFromPoint(POINT { x: x.round() as i32, y: y.round() as i32 });
        // A WebView2 page answers with its render-host child, owned by msedgewebview2.exe: the top-level window is ours.
        let root = GetAncestor(hwnd, GA_ROOT);
        let root = if root.0.is_null() { hwnd } else { root };
        let mut pid = 0u32;
        GetWindowThreadProcessId(root, Some(&mut pid as *mut u32));
        pid == std::process::id()
    }
}

/// The image name (`Code.exe`) of the process that owns the foreground window, for focus awareness; read once per permission request, compared by the page and dropped (never logged).
/// None when there is no foreground window, it is one of ours (Settings, the desktop cat, the chat), or the process cannot be queried.
pub fn foreground_app(_app: &AppHandle) -> Option<String> {
    unsafe {
        let fg = GetForegroundWindow();
        if fg.0.is_null() {
            return None;
        }
        let mut pid = 0u32;
        GetWindowThreadProcessId(fg, Some(&mut pid as *mut u32));
        if pid == std::process::id() {
            return None;
        }
        let handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid).ok()?;
        let mut buf = [0u16; 1024];
        let mut len = buf.len() as u32;
        let read = QueryFullProcessImageNameW(handle, PROCESS_NAME_WIN32, PWSTR(buf.as_mut_ptr()), &mut len);
        let _ = CloseHandle(handle);
        read.ok()?;
        crate::foreground::image_base_name(&String::from_utf16_lossy(&buf[..len as usize]))
    }
}

/// Nothing to detect: Windows always gives the pointer.
pub fn detect_pointer_feed() {}

// ── Island window ─────────────────────────────────────────────────────────────

fn hwnd_of(win: &WebviewWindow) -> Option<HWND> {
    let raw = win.hwnd().ok()?.0 as isize;
    if raw == 0 {
        return None;
    }
    Some(HWND(raw as *mut _))
}

/// Lets dropped files reach the app again.
///
/// wry installs its drop target by walking the webview's child windows **once**,
/// when the webview is created. WebView2 creates `Chrome_RenderWidgetHostHWND`
/// later and registers its own target on it; being the innermost window, that one
/// wins, and since the page has no HTML5 drop handler it refuses everything — the
/// "no drop" cursor, with nothing reaching Tauri. Revoking it makes OLE fall
/// through to the target wry registered on the parent widget, which is the one
/// that feeds Tauri's drag events.
///
/// Cheap and idempotent, so it is simply re-run whenever a drag might be starting.
pub fn unblock_webview_drops(app: &AppHandle) {
    for label in [WINDOW_LABEL, "settings"] {
        let Some(win) = app.get_webview_window(label) else { continue };
        let Some(hwnd) = hwnd_of(&win) else { continue };
        unsafe {
            let _ = EnumChildWindows(Some(hwnd), Some(revoke_render_widget), LPARAM(0));
        }
    }
}

unsafe extern "system" fn revoke_render_widget(hwnd: HWND, _: LPARAM) -> BOOL {
    let mut name = [0u16; 64];
    let len = unsafe { GetClassNameW(hwnd, &mut name) };
    if len > 0 {
        let class = String::from_utf16_lossy(&name[..len as usize]);
        if class == "Chrome_RenderWidgetHostHWND" {
            let _ = unsafe { RevokeDragDrop(hwnd) };
        }
    }
    true.into()
}

/// WS_EX_NOACTIVATE keeps clicks from stealing focus; WS_EX_TOOLWINDOW keeps the
/// island out of Alt-Tab.
pub fn make_non_activating(win: &WebviewWindow) {
    let Some(hwnd) = hwnd_of(win) else { return };
    unsafe {
        let ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
        let want = ex | WS_EX_NOACTIVATE.0 as isize | WS_EX_TOOLWINDOW.0 as isize;
        SetWindowLongPtrW(hwnd, GWL_EXSTYLE, want);
    }
}

/// Temporarily allow activation so a text field inside the island can be typed in.
pub fn set_activating(win: &WebviewWindow, activating: bool) {
    let Some(hwnd) = hwnd_of(win) else { return };
    unsafe {
        let ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
        let want = if activating {
            ex & !(WS_EX_NOACTIVATE.0 as isize)
        } else {
            ex | WS_EX_NOACTIVATE.0 as isize
        };
        SetWindowLongPtrW(hwnd, GWL_EXSTYLE, want);
    }
}

/// Click-through here is the poll's WS_EX_TRANSPARENT toggle, not a region.
pub fn set_input_region(_win: &WebviewWindow, _rect: Option<(f64, f64, f64, f64)>) {}

// ── Desktop cat window (sub-project H) ────────────────────────────────────────────────────────────────────────────────────────────────────

/// The desktop cat's window never takes focus and stays out of Alt-Tab, like the island's.
pub fn make_desktop_window(win: &WebviewWindow) {
    make_non_activating(win);
}

/// Windows lets an app put its windows where it wants.
pub fn desktop_positioned() -> bool {
    true
}

/// Puts the desktop window's top-left at (x, y) physical px.
pub fn place_desktop(win: &WebviewWindow, x: i32, y: i32, _monitor: usize, _monitor_origin: (i32, i32), _scale: f64) {
    let _ = win.set_position(tauri::PhysicalPosition::new(x, y));
}

/// Click-through is the poll's WS_EX_TRANSPARENT toggle (desktop.rs), not a region.
pub fn set_desktop_input(_win: &WebviewWindow, _rects: &[(f64, f64, f64, f64)]) {}

/// The system's double-click time in ms.
pub fn double_click_ms() -> Option<u32> {
    Some(unsafe { ::windows::Win32::UI::Input::KeyboardAndMouse::GetDoubleClickTime() })
}

/// Puts `text` on the clipboard as Unicode text (a path the user dropped on an agent's cat: the Sidekick copies it so they can paste it into that agent). True when it is there.
/// The clipboard may be held by another program for a moment, so opening it is tried a few times. Nothing is pasted anywhere: this only fills the clipboard.
pub fn copy_text(_app: &AppHandle, text: &str) -> bool {
    use ::windows::Win32::System::DataExchange::{CloseClipboard, EmptyClipboard, OpenClipboard, SetClipboardData};
    use ::windows::Win32::Foundation::GlobalFree;
    use ::windows::Win32::System::Memory::{GlobalAlloc, GlobalLock, GlobalUnlock, GMEM_MOVEABLE};
    use ::windows::Win32::System::Ole::CF_UNICODETEXT;
    let wide: Vec<u16> = text.encode_utf16().chain(std::iter::once(0)).collect();
    // SAFETY: the clipboard is opened and closed in this function; the global memory is sized for `wide`, locked while it is written, and either owned by the system after
    // `SetClipboardData` succeeds or freed here when it did not.
    unsafe {
        let mut opened = false;
        for _ in 0..5 {
            if OpenClipboard(None).is_ok() {
                opened = true;
                break;
            }
            std::thread::sleep(std::time::Duration::from_millis(15));
        }
        if !opened {
            return false;
        }
        let mut ok = false;
        if EmptyClipboard().is_ok() {
            if let Ok(mem) = GlobalAlloc(GMEM_MOVEABLE, wide.len() * 2) {
                let dst = GlobalLock(mem) as *mut u16;
                if !dst.is_null() {
                    std::ptr::copy_nonoverlapping(wide.as_ptr(), dst, wide.len());
                    let _ = GlobalUnlock(mem);
                    ok = SetClipboardData(u32::from(CF_UNICODETEXT.0), Some(HANDLE(mem.0))).is_ok();
                }
                if !ok {
                    let _ = GlobalFree(Some(mem));
                }
            }
        }
        let _ = CloseClipboard();
        ok
    }
}

/// Seconds since the last keyboard or mouse input of this session (`GetLastInputInfo`), or None when the system does not say. The Sidekick asks for it when a hook event comes, when
/// the island opens and on an unlock: it never runs on a timer.
pub fn idle_seconds() -> Option<u64> {
    use ::windows::Win32::System::SystemInformation::GetTickCount;
    use ::windows::Win32::UI::Input::KeyboardAndMouse::{GetLastInputInfo, LASTINPUTINFO};
    let mut info = LASTINPUTINFO { cbSize: std::mem::size_of::<LASTINPUTINFO>() as u32, dwTime: 0 };
    // SAFETY: `info` is a valid LASTINPUTINFO with its size set, which is all the call asks for.
    unsafe {
        if !GetLastInputInfo(&mut info).as_bool() {
            return None;
        }
        Some(crate::sidekick_presence::idle_seconds_from_ticks(GetTickCount(), info.dwTime))
    }
}

/// Whether this session is locked right now (`WTSSessionInfoEx`: `SessionFlags`), or None when the system does not say.
fn session_locked() -> Option<bool> {
    use ::windows::Win32::System::RemoteDesktop::{WTSFreeMemory, WTSQuerySessionInformationW, WTSSessionInfoEx, WTSINFOEXW, WTS_CURRENT_SERVER_HANDLE, WTS_CURRENT_SESSION};
    let mut buf = PWSTR::null();
    let mut len = 0u32;
    // SAFETY: the call fills `buf` with a buffer of `len` bytes that WTSFreeMemory frees, and the struct is read only when the buffer is as big as one and says it is level 1.
    unsafe {
        WTSQuerySessionInformationW(Some(WTS_CURRENT_SERVER_HANDLE), WTS_CURRENT_SESSION, WTSSessionInfoEx, &mut buf, &mut len).ok()?;
        let flags = if buf.is_null() || (len as usize) < std::mem::size_of::<WTSINFOEXW>() {
            None
        } else {
            let info = std::ptr::read_unaligned(buf.0 as *const WTSINFOEXW);
            (info.Level == 1).then(|| info.Data.WTSInfoExLevel1.SessionFlags)
        };
        WTSFreeMemory(buf.0 as *mut _);
        flags.and_then(session_locked_from_flags)
    }
}

static AWAY: std::sync::OnceLock<Box<dyn Fn(AwaySource, bool) + Send + Sync>> = std::sync::OnceLock::new();

/// `GUID_CONSOLE_DISPLAY_STATE` ({6fe69556-704a-47a0-8f24-c28d936fda47}), written out: the crate keeps it in `Win32_System_SystemServices`, a feature this app does not enable.
const GUID_CONSOLE_DISPLAY_STATE: ::windows::core::GUID = ::windows::core::GUID::from_u128(0x6fe69556_704a_47a0_8f24_c28d936fda47);

/// Session lock and unlock (`WM_WTSSESSION_CHANGE`) and the display turning off or on (`WM_POWERBROADCAST` with the console display state): `notify(AwaySource::Locked, on)` and
/// `notify(AwaySource::Off, on)`, two causes the caller combines. A message-only window on its own thread receives them and blocks in `GetMessageW`, so nothing polls.
unsafe extern "system" fn away_proc(hwnd: HWND, msg: u32, wp: ::windows::Win32::Foundation::WPARAM, lp: LPARAM) -> ::windows::Win32::Foundation::LRESULT {
    use ::windows::Win32::System::Power::POWERBROADCAST_SETTING;
    use ::windows::Win32::UI::WindowsAndMessaging::{
        DefWindowProcW, PBT_POWERSETTINGCHANGE, WM_POWERBROADCAST, WM_WTSSESSION_CHANGE, WTS_CONSOLE_CONNECT, WTS_CONSOLE_DISCONNECT, WTS_REMOTE_CONNECT, WTS_REMOTE_DISCONNECT, WTS_SESSION_LOCK,
        WTS_SESSION_UNLOCK,
    };
    let tell = |source: AwaySource, on: bool| {
        if let Some(f) = AWAY.get() {
            f(source, on);
        }
    };
    match msg {
        WM_WTSSESSION_CHANGE => {
            match wp.0 as u32 {
                // A lock is away, and so is a switch to another user (this session is disconnected from the console) or a remote session ending: the same "locked" cause.
                WTS_SESSION_LOCK | WTS_CONSOLE_DISCONNECT | WTS_REMOTE_DISCONNECT => tell(AwaySource::Locked, true),
                WTS_SESSION_UNLOCK => tell(AwaySource::Locked, false),
                // Switching back to this session shows its lock screen when it is still locked: the unlock is told only when the session is known not to be (the WTS_SESSION_UNLOCK that
                // follows the sign-in is the one that ends the away then).
                WTS_CONSOLE_CONNECT | WTS_REMOTE_CONNECT => {
                    if unlock_is_real(session_locked()) {
                        tell(AwaySource::Locked, false);
                    }
                }
                _ => {}
            }
            ::windows::Win32::Foundation::LRESULT(0)
        }
        WM_POWERBROADCAST if wp.0 as u32 == PBT_POWERSETTINGCHANGE => {
            let s = unsafe { &*(lp.0 as *const POWERBROADCAST_SETTING) };
            if s.PowerSetting == GUID_CONSOLE_DISPLAY_STATE && s.DataLength >= 1 {
                // 0 off, 1 on, 2 dimmed: only off and on are news.
                if let Some(off) = display_away(s.Data[0]) {
                    tell(AwaySource::Off, off);
                }
            }
            ::windows::Win32::Foundation::LRESULT(1)
        }
        _ => unsafe { DefWindowProcW(hwnd, msg, wp, lp) },
    }
}

/// Starts listening (once). `notify(source, true)` while the session is locked (`Locked`) or the display is off (`Off`), `false` when that ends.
pub fn watch_away(notify: impl Fn(AwaySource, bool) + Send + Sync + 'static) {
    if AWAY.set(Box::new(notify)).is_err() {
        return;
    }
    std::thread::spawn(|| unsafe {
        use ::windows::core::w;
        use ::windows::Win32::System::LibraryLoader::GetModuleHandleW;
        use ::windows::Win32::System::Power::RegisterPowerSettingNotification;
        use ::windows::Win32::System::RemoteDesktop::{WTSRegisterSessionNotification, NOTIFY_FOR_THIS_SESSION};
        use ::windows::Win32::UI::WindowsAndMessaging::{
            CreateWindowExW, DispatchMessageW, GetMessageW, RegisterClassW, TranslateMessage, DEVICE_NOTIFY_WINDOW_HANDLE, HWND_MESSAGE, MSG, WINDOW_EX_STYLE, WINDOW_STYLE, WNDCLASSW,
        };
        let Ok(module) = GetModuleHandleW(None) else { return };
        let class = WNDCLASSW { lpfnWndProc: Some(away_proc), hInstance: module.into(), lpszClassName: w!("NotchMeowAway"), ..Default::default() };
        RegisterClassW(&class);
        let Ok(hwnd) = CreateWindowExW(WINDOW_EX_STYLE(0), w!("NotchMeowAway"), w!(""), WINDOW_STYLE(0), 0, 0, 0, 0, Some(HWND_MESSAGE), None, Some(module.into()), None) else { return };
        let _ = WTSRegisterSessionNotification(hwnd, NOTIFY_FOR_THIS_SESSION);
        let _ = RegisterPowerSettingNotification(::windows::Win32::Foundation::HANDLE(hwnd.0), &GUID_CONSOLE_DISPLAY_STATE, DEVICE_NOTIFY_WINDOW_HANDLE);
        let mut msg = MSG::default();
        // 0 is WM_QUIT and -1 an error: only a message (> 0) is dispatched.
        while GetMessageW(&mut msg, None, 0, 0).0 > 0 {
            let _ = TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    });
}

/// True when the foreground window belongs to another process and covers a whole monitor (a fullscreen game or video, F11 in a browser; not a maximized window, which has a title
/// bar): the desktop cat steps aside. The desktop itself and the taskbar are never "fullscreen". `monitors` are (x, y, width, height) in physical px.
pub fn fullscreen_app_covers(monitors: &[(i32, i32, u32, u32)]) -> bool {
    unsafe {
        let fg = GetForegroundWindow();
        if fg.0.is_null() {
            return false;
        }
        let mut pid = 0u32;
        GetWindowThreadProcessId(fg, Some(&mut pid as *mut u32));
        if pid == std::process::id() {
            return false;
        }
        let mut name = [0u16; 64];
        let len = GetClassNameW(fg, &mut name);
        if len > 0 {
            let class = String::from_utf16_lossy(&name[..len as usize]);
            if matches!(class.as_str(), "Progman" | "WorkerW" | "Shell_TrayWnd" | "Shell_SecondaryTrayWnd") {
                return false;
            }
        }
        let mut r = RECT::default();
        if GetWindowRect(fg, &mut r).is_err() {
            return false;
        }
        // The title bar is what a maximized window has and a fullscreen one does not: with an auto-hiding taskbar a maximized window's rectangle is the whole monitor (and a bit more).
        let style = GetWindowLongPtrW(fg, GWL_STYLE) as u32;
        crate::desktop::covers_monitor(style, (r.left, r.top, r.right, r.bottom), monitors)
    }
}
