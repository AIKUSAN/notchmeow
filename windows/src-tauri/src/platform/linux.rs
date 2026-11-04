// Linux: XDG directories for files, xdg-open for links and folders, and
// gtk-layer-shell for the island window.
//
// Wayland gives an app no global cursor position and no say over where its
// window goes, so the island works differently from Windows:
//   * it is a layer-shell surface anchored to the top edge, above everything,
//     on compositors that support it (COSMIC, KDE, wlroots — not GNOME);
//   * click-through is the window's input region, set to the island shape, so
//     the compositor itself sends every other click to whatever is underneath;
//   * the cursor comes from the page's own mouse events, which only fire over
//     the island — the cat's eyes follow the pointer there, not across the screen.

mod drag;

use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::Mutex;

use gtk::glib::translate::ToGlibPtr;
use gtk::prelude::*;
use tauri::{AppHandle, WebviewWindow};

use super::{home_dir, DragDone, LocalTime};
use crate::desktop::AwaySource;
use crate::sidekick_presence::unlock_is_real;

/// File name of the Claude Code relay.
pub const HOOK_EXE: &str = "notchmeow-hook";

/// Environment variable holding the home directory.
pub const HOME_VAR: &str = "HOME";

// ── Files ─────────────────────────────────────────────────────────────────────

/// An XDG base directory (`$XDG_CONFIG_HOME` …), or its fallback under the home
/// directory when it is unset or not absolute.
fn xdg(var: &str, fallback: &str) -> PathBuf {
    std::env::var_os(var)
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .unwrap_or_else(|| home_dir().join(fallback))
}

/// ~/.config/notchmeow — preferences.
pub fn config_dir() -> PathBuf {
    xdg("XDG_CONFIG_HOME", ".config").join("notchmeow")
}

/// ~/.local/share/notchmeow — where notchmeow-hook, the inbox and the log live. The
/// relay has to sit at a stable path: an AppImage is mounted somewhere new on
/// every launch.
pub fn local_dir() -> PathBuf {
    xdg("XDG_DATA_HOME", ".local/share").join("notchmeow")
}

/// Environment the webview must inherit, set before any thread or process
/// starts.
///
/// Inside an AppImage, WebKit uses the GStreamer bundled with it, and GStreamer
/// keeps its plugin registry in ~/.cache/gstreamer-1.0 by default — the same
/// file the system's GStreamer uses. The AppImage is mounted somewhere new on
/// every launch, so each launch would rewrite the system's registry with
/// plugin paths that vanish once NotchMeow quits. Give ours its own file.
pub fn prepare_environment() {
    if std::env::var_os("APPIMAGE").is_none() || std::env::var_os("GST_REGISTRY").is_some() {
        return;
    }
    let cache = xdg("XDG_CACHE_HOME", ".cache").join("notchmeow");
    if std::fs::create_dir_all(&cache).is_ok() {
        std::env::set_var("GST_REGISTRY", cache.join("gstreamer-registry.bin"));
    }
}

pub fn local_time() -> LocalTime {
    let mut tm: libc::tm = unsafe { std::mem::zeroed() };
    unsafe {
        let now = libc::time(std::ptr::null_mut());
        libc::localtime_r(&now, &mut tm);
    }
    LocalTime {
        year: (tm.tm_year + 1900) as u32,
        month: (tm.tm_mon + 1) as u32,
        day: tm.tm_mday as u32,
        hour: tm.tm_hour as u32,
        minute: tm.tm_min as u32,
        second: tm.tm_sec as u32,
    }
}

/// Creates `dir` and closes it to other users. The log, the inbox of dropped
/// files and the relay binary live under these directories; with the default
/// umask they would come out 0755 and readable by anyone on the machine.
pub fn ensure_private_dir(dir: &Path) -> std::io::Result<()> {
    std::fs::create_dir_all(dir)?;
    std::fs::set_permissions(dir, std::fs::Permissions::from_mode(0o700))
}

/// True when `dir` is a real directory (not a symlink), owned by us, with no
/// access for group or others: what `$XDG_RUNTIME_DIR` promises, checked
/// rather than assumed, since the socket in it decides who can answer a
/// permission request.
fn is_private_dir(dir: &Path) -> bool {
    use std::os::unix::fs::MetadataExt;
    std::fs::symlink_metadata(dir)
        .map(|m| {
            m.file_type().is_dir() && m.uid() == unsafe { libc::getuid() } && m.mode() & 0o077 == 0
        })
        .unwrap_or(false)
}

/// Where notchmeow-hook finds us: `$XDG_RUNTIME_DIR/notchmeow.sock`, or
/// `/run/user/<uid>/notchmeow.sock` when the variable is missing. A directory
/// that is not ours and private means no relay at all — never a fallback to a
/// shared place like /tmp. Must match `socket_path()` in hook/src/unix.rs
/// exactly.
pub fn relay_socket_path() -> Option<PathBuf> {
    let dir = std::env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .unwrap_or_else(|| PathBuf::from(format!("/run/user/{}", unsafe { libc::getuid() })));
    is_private_dir(&dir).then(|| dir.join("notchmeow.sock"))
}

// ── Processes ─────────────────────────────────────────────────────────────────

/// Nothing to hide: a spawned process only gets a terminal if it asks for one.
pub fn no_console(cmd: &mut Command) -> &mut Command {
    cmd
}

pub fn open_url(url: &str) {
    let _ = Command::new("xdg-open").arg(url).spawn();
}

/// Anthropic ships no Claude desktop app for Linux, so the pill has nothing to open here and the page shows no button.
pub const CLAUDE_APP: bool = false;

pub fn open_claude_app() -> bool {
    false
}

/// Starts a GTK drag of these files out of the island (linux/drag.rs). Returns at once; `done` is called when the drag ends.
pub fn drag_out(win: &WebviewWindow, paths: Vec<PathBuf>, done: DragDone) {
    match win.gtk_window() {
        Ok(gw) => drag::begin(&gw, &paths, done),
        Err(e) => done(Err(e.to_string())),
    }
}

/// Linux has no system share.
pub const SHARE: bool = false;

pub fn share_files(_win: &WebviewWindow, _paths: &[PathBuf]) -> Result<(), String> {
    Err("There is no system share on this system. Use Show in folder.".into())
}

/// Show in the file manager with the file selected, through the freedesktop `FileManager1.ShowItems` call (GNOME Files, Dolphin, Nautilus, Thunar and others answer it); a system
/// whose file manager does not, gets the folder opened instead. `gdbus` ships with GLib, so this adds no dependency.
pub fn reveal_file(path: &Path) {
    let asked = Command::new("gdbus").args(crate::dragout::show_items_args(path)).status().map(|s| s.success()).unwrap_or(false);
    if !asked {
        if let Some(parent) = path.parent() {
            reveal_folder(&parent.to_string_lossy());
        }
    }
}

pub fn reveal_folder(path: &str) {
    let _ = Command::new("xdg-open").arg(path).spawn();
}

/// Our own `which`: the first executable file named `stem` on $PATH.
pub fn find_on_path(stem: &str) -> Option<PathBuf> {
    let dirs = std::env::var_os("PATH")?;
    std::env::split_paths(&dirs)
        .map(|dir| dir.join(stem))
        .find(|p| {
            std::fs::metadata(p)
                .map(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
                .unwrap_or(false)
        })
}

// ── Cursor ────────────────────────────────────────────────────────────────────

/// Click-through here is the input region, never the poll's `WS_EX_TRANSPARENT` toggle, so this stays false even where the pointer can be read (`pointer_feed`, X11).
pub const CURSOR_POLL: bool = false;

/// The pointer in physical root pixels, under X11 (`pointer_feed`); nothing under Wayland.
pub fn cursor_physical() -> Option<(f64, f64)> {
    if !pointer_feed() {
        return None;
    }
    x11_pointer().map(|(x, y, _)| (x, y))
}

pub fn left_button_down() -> bool {
    false
}

// ── The pointer feed (X11 only) ───────────────────────────────────────────────────────────────

/// Whether GDK runs on its X11 backend, where the pointer can be read anywhere on the screen. A Wayland session gives an app no global pointer (XWayland would answer with a stale
/// one), so it is not counted even if libX11 can connect. Set once by `detect_pointer_feed`.
static X11_POINTER: AtomicBool = AtomicBool::new(false);

pub fn pointer_feed() -> bool {
    X11_POINTER.load(Ordering::Relaxed)
}

/// The feed needs GDK on X11 and no Wayland session around it: with `GDK_BACKEND=x11` inside a Wayland session GDK's display is an X11 one (XWayland), whose pointer is stale over native Wayland windows.
fn x11_feed(gdk_is_x11: bool, wayland_display_set: bool) -> bool {
    gdk_is_x11 && !wayland_display_set
}

/// Main thread, once, at setup: is GDK's display the X11 one, in a session that is not Wayland?
pub fn detect_pointer_feed() {
    let gdk_x11 = gtk::gdk::Display::default().map(|d| d.type_().name() == "GdkX11Display").unwrap_or(false);
    let x11 = x11_feed(gdk_x11, std::env::var_os("WAYLAND_DISPLAY").is_some());
    X11_POINTER.store(x11, Ordering::Relaxed);
    crate::log::line(format!("pointer feed: {}", if x11 { "X11 (global pointer)" } else { "none (no global pointer)" }));
}

mod x11 {
    use std::os::raw::{c_char, c_int, c_long, c_uint, c_ulong, c_void};
    // libX11 is always there: GTK 3 links it, even in a Wayland session. These are the three calls the pointer read needs.
    #[link(name = "X11")]
    extern "C" {
        pub fn XOpenDisplay(name: *const c_char) -> *mut c_void;
        pub fn XDefaultRootWindow(display: *mut c_void) -> c_ulong;
        pub fn XQueryPointer(display: *mut c_void, w: c_ulong, root: *mut c_ulong, child: *mut c_ulong, root_x: *mut c_int, root_y: *mut c_int, win_x: *mut c_int, win_y: *mut c_int, mask: *mut c_uint) -> c_int;
        // Focus awareness: the active window's class (`foreground_app`).
        pub fn XInternAtom(display: *mut c_void, name: *const c_char, only_if_exists: c_int) -> c_ulong;
        pub fn XGetWindowProperty(display: *mut c_void, w: c_ulong, property: c_ulong, offset: c_long, length: c_long, delete: c_int, req_type: c_ulong, actual_type: *mut c_ulong, actual_format: *mut c_int, nitems: *mut c_ulong, bytes_after: *mut c_ulong, prop: *mut *mut u8) -> c_int;
        pub fn XGetClassHint(display: *mut c_void, w: c_ulong, hint: *mut XClassHint) -> c_int;
        pub fn XFree(data: *mut c_void) -> c_int;
    }
    /// Xlib's `XClassHint`: both strings are Xlib's to allocate and ours to `XFree`.
    #[repr(C)]
    pub struct XClassHint {
        pub res_name: *mut c_char,
        pub res_class: *mut c_char,
    }
    // GTK already links the library. GDK's connection and its error trap, because a `BadWindow` for a window closed between the two reads would reach Xlib's default handler, which exits the process.
    #[link(name = "gdk-3")]
    extern "C" {
        pub fn gdk_x11_display_get_xdisplay(display: *mut c_void) -> *mut c_void;
        pub fn gdk_x11_display_error_trap_push(display: *mut c_void);
        pub fn gdk_x11_display_error_trap_pop_ignored(display: *mut c_void);
    }
}

/// Button1Mask, Button2Mask and Button3Mask of an X pointer state (the wheel's buttons 4 and 5 are not buttons held).
fn buttons_down(mask: u32) -> bool {
    mask & ((1 << 8) | (1 << 9) | (1 << 10)) != 0
}

/// The pointer's root position (physical px) and whether a button is held, from a connection of the calling thread's own: an Xlib display is not shared between threads, so each caller thread (the island's poll, the desktop cat's poll thread, and the main thread for `desktop_cursor` and
/// `target_monitor`) opens and keeps its own. None when X cannot be reached.
fn x11_pointer() -> Option<(f64, f64, bool)> {
    use std::cell::Cell;
    use std::os::raw::{c_int, c_uint, c_ulong, c_void};
    thread_local! {
        static DISPLAY: Cell<usize> = const { Cell::new(0) };
    }
    DISPLAY.with(|cell| unsafe {
        let mut display = cell.get() as *mut c_void;
        if display.is_null() {
            display = x11::XOpenDisplay(std::ptr::null());
            if display.is_null() {
                return None;
            }
            cell.set(display as usize);
        }
        let (mut root, mut child): (c_ulong, c_ulong) = (0, 0);
        let (mut rx, mut ry, mut wx, mut wy): (c_int, c_int, c_int, c_int) = (0, 0, 0, 0);
        let mut mask: c_uint = 0;
        let ok = x11::XQueryPointer(display, x11::XDefaultRootWindow(display), &mut root, &mut child, &mut rx, &mut ry, &mut wx, &mut wy, &mut mask);
        (ok != 0).then(|| (rx as f64, ry as f64, buttons_down(mask)))
    })
}

pub fn any_button_down() -> bool {
    pointer_feed() && x11_pointer().map(|(_, _, down)| down).unwrap_or(false)
}

/// Whether the window under the pointer belongs to this app (GDK answers `None` for another app's window). GDK is main-thread only, so the poll thread asks the main thread and waits at
/// most 40 ms; this runs at button presses only.
pub fn press_is_own(app: &AppHandle, _x: f64, _y: f64) -> bool {
    if !pointer_feed() {
        return false;
    }
    let (tx, rx) = std::sync::mpsc::channel();
    let asked = app.run_on_main_thread(move || {
        let own = gtk::gdk::Display::default()
            .and_then(|d| d.default_seat())
            .and_then(|s| s.pointer())
            .map(|p| p.window_at_position().0.is_some())
            .unwrap_or(false);
        let _ = tx.send(own);
    });
    asked.is_ok() && rx.recv_timeout(std::time::Duration::from_millis(40)).unwrap_or(false)
}

/// The window class (`Code`, `kitty`) of the X11 active window, for focus awareness; read once per permission request, compared by the page and dropped (never logged). None under
/// Wayland, when no window is active, on a failed read, or after 40 ms: GDK is main-thread only, so the poll asks the main thread (the `press_is_own` pattern).
pub fn foreground_app(app: &AppHandle) -> Option<String> {
    if !pointer_feed() {
        return None;
    }
    let (tx, rx) = std::sync::mpsc::channel();
    app.run_on_main_thread(move || {
        let _ = tx.send(active_window_class());
    })
    .ok()?;
    rx.recv_timeout(std::time::Duration::from_millis(40)).ok().flatten()
}

/// Main thread only. Reads `_NET_ACTIVE_WINDOW` of the root and that window's class hint on GDK's own X connection, inside GDK's error trap.
fn active_window_class() -> Option<String> {
    use std::os::raw::{c_int, c_ulong, c_void};
    const XA_WINDOW: c_ulong = 33;
    let gdk = gtk::gdk::Display::default()?;
    let gdk_ptr: *mut c_void = ToGlibPtr::<*mut gtk::gdk::ffi::GdkDisplay>::to_glib_none(&gdk).0 as *mut c_void;
    unsafe {
        let xd = x11::gdk_x11_display_get_xdisplay(gdk_ptr);
        if xd.is_null() {
            return None;
        }
        x11::gdk_x11_display_error_trap_push(gdk_ptr);
        let class = (|| {
            let atom = x11::XInternAtom(xd, c"_NET_ACTIVE_WINDOW".as_ptr(), 1);
            if atom == 0 {
                return None;
            }
            let (mut kind, mut format, mut items, mut after): (c_ulong, c_int, c_ulong, c_ulong) = (0, 0, 0, 0);
            let mut prop: *mut u8 = std::ptr::null_mut();
            let status = x11::XGetWindowProperty(xd, x11::XDefaultRootWindow(xd), atom, 0, 1, 0, XA_WINDOW, &mut kind, &mut format, &mut items, &mut after, &mut prop);
            let window = if status == 0 && !prop.is_null() && format == 32 && items >= 1 { *(prop as *const c_ulong) } else { 0 };
            if !prop.is_null() {
                x11::XFree(prop as *mut c_void);
            }
            if window == 0 {
                return None;
            }
            let mut hint = x11::XClassHint { res_name: std::ptr::null_mut(), res_class: std::ptr::null_mut() };
            if x11::XGetClassHint(xd, window, &mut hint) == 0 {
                return None;
            }
            let class = (!hint.res_class.is_null()).then(|| std::ffi::CStr::from_ptr(hint.res_class).to_string_lossy().into_owned());
            if !hint.res_name.is_null() {
                x11::XFree(hint.res_name as *mut c_void);
            }
            if !hint.res_class.is_null() {
                x11::XFree(hint.res_class as *mut c_void);
            }
            class
        })();
        x11::gdk_x11_display_error_trap_pop_ignored(gdk_ptr);
        class
    }
}

#[cfg(test)]
mod x11_tests {
    use super::*;

    #[test]
    fn only_the_three_buttons_count_as_held() {
        assert!(buttons_down(1 << 8), "button 1");
        assert!(buttons_down(1 << 9), "button 2");
        assert!(buttons_down(1 << 10), "button 3");
        assert!(buttons_down((1 << 8) | 0x4), "a button with control held");
        assert!(!buttons_down(0), "nothing held");
        assert!(!buttons_down(0x4 | 0x1), "control and shift alone");
        assert!(!buttons_down((1 << 11) | (1 << 12)), "the wheel's buttons 4 and 5 are not held buttons");
    }

    #[test]
    fn xwayland_is_not_a_global_pointer() {
        assert!(x11_feed(true, false), "a real X11 session");
        assert!(!x11_feed(true, true), "GDK_BACKEND=x11 inside a Wayland session (XWayland) answers with a stale pointer");
        assert!(!x11_feed(false, false), "GDK on Wayland");
        assert!(!x11_feed(false, true), "GDK on Wayland, WAYLAND_DISPLAY set");
    }

    #[test]
    fn without_the_feed_nothing_is_read() {
        // detect_pointer_feed has not run in a unit test, so the feed is off and no X connection is opened.
        assert!(!pointer_feed());
        assert_eq!(cursor_physical(), None);
        assert!(!any_button_down());
    }
}

// ── Island window ─────────────────────────────────────────────────────────────

/// The few gtk-layer-shell calls we need, straight from the C library.
mod layer {
    use gtk::ffi::GtkWindow;
    use std::os::raw::{c_char, c_int};

    pub const LAYER_OVERLAY: c_int = 3;
    pub const LAYER_TOP: c_int = 2;
    pub const EDGE_LEFT: c_int = 0;
    pub const EDGE_TOP: c_int = 2;
    pub const KEYBOARD_NONE: c_int = 0;
    pub const KEYBOARD_ON_DEMAND: c_int = 2;

    #[link(name = "gtk-layer-shell")]
    extern "C" {
        pub fn gtk_layer_is_supported() -> c_int;
        pub fn gtk_layer_init_for_window(window: *mut GtkWindow);
        pub fn gtk_layer_set_namespace(window: *mut GtkWindow, name_space: *const c_char);
        pub fn gtk_layer_set_layer(window: *mut GtkWindow, layer: c_int);
        pub fn gtk_layer_set_anchor(window: *mut GtkWindow, edge: c_int, anchor: c_int);
        pub fn gtk_layer_set_exclusive_zone(window: *mut GtkWindow, zone: c_int);
        pub fn gtk_layer_set_keyboard_mode(window: *mut GtkWindow, mode: c_int);
        pub fn gtk_layer_set_margin(window: *mut GtkWindow, edge: c_int, margin_size: c_int);
        pub fn gtk_layer_set_monitor(window: *mut GtkWindow, monitor: *mut gtk::gdk::ffi::GdkMonitor);
    }
}

/// True once the island window is a layer-shell surface.
static LAYER_SURFACE: AtomicBool = AtomicBool::new(false);

/// The input region last asked for, re-applied whenever the window is mapped:
/// GTK resets it to the whole window on map. Until the page reports the island
/// shape it is empty, so nothing takes the mouse.
type Region = Option<(f64, f64, f64, f64)>;
static INPUT_REGION: Mutex<Region> = Mutex::new(Some((0.0, 0.0, 0.0, 0.0)));

fn gtk_window_ptr(win: &gtk::ApplicationWindow) -> *mut gtk::ffi::GtkWindow {
    let w: &gtk::Window = win.upcast_ref();
    w.to_glib_none().0
}

/// WebKitGTK has no competing drop target to remove.
pub fn unblock_webview_drops(_app: &AppHandle) {}

/// Turns the island into an overlay surface on the top edge that never takes
/// the keyboard. Must run before the window is first shown: a layer surface
/// cannot be made out of a window the compositor already knows.
///
/// Without layer-shell (GNOME, X11, or NOTCHMEOW_LAYER_SHELL=0) the window stays
/// an ordinary always-on-top window that refuses focus; where it lands is then
/// up to the window manager.
pub fn make_non_activating(win: &WebviewWindow) {
    let Ok(gw) = win.gtk_window() else { return };
    // NOTCHMEOW_LAYER_SHELL=0 is the way out on a compositor where it misbehaves.
    let wanted = std::env::var("NOTCHMEOW_LAYER_SHELL").map(|v| v != "0").unwrap_or(true);
    let supported = unsafe { layer::gtk_layer_is_supported() } != 0;
    if !wanted || !supported || gw.is_realized() {
        let why = if !wanted {
            "NOTCHMEOW_LAYER_SHELL=0"
        } else if supported {
            "window already shown"
        } else {
            "compositor has no layer-shell"
        };
        crate::log::line(format!("island is a regular window ({why})"));
        gw.set_accept_focus(false);
        return;
    }
    // tao gives undecorated Wayland windows an empty titlebar to force
    // client-side decorations. A layer surface has none, and a client-decorated
    // GtkWindow recomputes its own input region (shadow margins included) on
    // every map, over ours.
    gw.set_titlebar(None::<&gtk::Widget>);
    let ptr = gtk_window_ptr(&gw);
    unsafe {
        layer::gtk_layer_init_for_window(ptr);
        layer::gtk_layer_set_namespace(ptr, c"notchmeow".as_ptr());
        layer::gtk_layer_set_layer(ptr, layer::LAYER_OVERLAY);
        // Top edge only: the compositor centres the surface horizontally.
        layer::gtk_layer_set_anchor(ptr, layer::EDGE_TOP, 1);
        // -1: sit right against the screen edge, over any top panel, the way
        // the Mac island sits in the notch.
        layer::gtk_layer_set_exclusive_zone(ptr, -1);
        layer::gtk_layer_set_keyboard_mode(ptr, layer::KEYBOARD_NONE);
    }
    // WebKitGTK in a freshly mapped layer surface never paints its first frame
    // (seen on COSMIC, and reproduced with a bare GTK window + WebKitGTK, no
    // Tauri involved): the surface stays empty. Unmapping and mapping it once,
    // right after the first map, gets it drawing for good.
    let remapped = std::cell::Cell::new(false);
    gw.connect_map_event(move |w, _| {
        apply_input_region(w, *INPUT_REGION.lock().unwrap());
        if !remapped.replace(true) {
            let w = w.clone();
            gtk::glib::idle_add_local_once(move || {
                w.hide();
                w.show_all();
                apply_input_region(&w, *INPUT_REGION.lock().unwrap());
            });
        }
        gtk::glib::Propagation::Proceed
    });
    LAYER_SURFACE.store(true, Ordering::Relaxed);
    crate::log::line("island is a layer-shell overlay");
}

/// Temporarily allow keyboard focus so a text field inside the island can be
/// typed in.
pub fn set_activating(win: &WebviewWindow, activating: bool) {
    let Ok(gw) = win.gtk_window() else { return };
    // The island is created `focusable: false` (tauri.linux.conf.json), so GTK
    // refuses focus until we say otherwise — on a layer surface too.
    gw.set_accept_focus(activating);
    if LAYER_SURFACE.load(Ordering::Relaxed) {
        let mode = if activating { layer::KEYBOARD_ON_DEMAND } else { layer::KEYBOARD_NONE };
        unsafe { layer::gtk_layer_set_keyboard_mode(gtk_window_ptr(&gw), mode) };
    }
}

/// Only this rectangle (window-logical pixels) takes the mouse; `None` means
/// the whole window does. Everything outside goes to the window underneath.
pub fn set_input_region(win: &WebviewWindow, rect: Region) {
    *INPUT_REGION.lock().unwrap() = rect;
    let Ok(gw) = win.gtk_window() else { return };
    apply_input_region(&gw, rect);
}

fn apply_input_region(gw: &impl IsA<gtk::Widget>, rect: Region) {
    match rect {
        None => gw.input_shape_combine_region(None),
        Some((x, y, w, h)) => {
            let Some(gdk_window) = gw.window() else { return };
            let region = gtk::cairo::Region::create_rectangle(&gtk::cairo::RectangleInt::new(
                x.floor() as i32,
                y.floor() as i32,
                w.ceil().max(0.0) as i32,
                h.ceil().max(0.0) as i32,
            ));
            gdk_window.input_shape_combine_region(&region, 0, 0);
        }
    }
}

// ── Desktop cat window (sub-project H) ────────────────────────────────────────────────────────────────────────────────────────────────────

/// True once the desktop cat's window is a layer-shell surface.
static DESKTOP_LAYER: AtomicBool = AtomicBool::new(false);
/// The monitor (its index) the layer surface was last put on, so it is only moved to another output when the cat changes screen.
static DESKTOP_MONITOR: AtomicUsize = AtomicUsize::new(usize::MAX);
/// The input region last asked for (the cat's shape), re-applied whenever the window is mapped: GTK resets it to the whole window on map. Empty until the page reports a layout,
/// so nothing takes the mouse.
static DESKTOP_REGION: Mutex<Vec<(f64, f64, f64, f64)>> = Mutex::new(Vec::new());

/// Makes the desktop cat's window a layer-shell surface on the TOP layer, anchored at the top left and placed with margins, that never takes the keyboard. The top layer (not the
/// overlay the island uses) is drawn below fullscreen windows, so the cat steps aside over a fullscreen app by itself. Must run before the window is first shown.
///
/// Without layer-shell (GNOME, X11, or NOTCHMEOW_LAYER_SHELL=0) the window stays an ordinary always-on-top window that refuses focus; on X11 its position is ours, on GNOME's
/// Wayland session it is the compositor's (see `desktop_positioned`).
pub fn make_desktop_window(win: &WebviewWindow) {
    let Ok(gw) = win.gtk_window() else { return };
    let wanted = std::env::var("NOTCHMEOW_LAYER_SHELL").map(|v| v != "0").unwrap_or(true);
    let supported = unsafe { layer::gtk_layer_is_supported() } != 0;
    if !wanted || !supported || gw.is_realized() {
        crate::log::line("desktop cat is a regular window");
        gw.set_accept_focus(false);
        gw.connect_map_event(|w, _| {
            apply_rects(w, &DESKTOP_REGION.lock().unwrap());
            gtk::glib::Propagation::Proceed
        });
        return;
    }
    // See make_non_activating: a layer surface has no titlebar, and a client-decorated GtkWindow recomputes its own input region on every map.
    gw.set_titlebar(None::<&gtk::Widget>);
    let ptr = gtk_window_ptr(&gw);
    unsafe {
        layer::gtk_layer_init_for_window(ptr);
        layer::gtk_layer_set_namespace(ptr, c"notchmeow-cat".as_ptr());
        layer::gtk_layer_set_layer(ptr, layer::LAYER_TOP);
        layer::gtk_layer_set_anchor(ptr, layer::EDGE_TOP, 1);
        layer::gtk_layer_set_anchor(ptr, layer::EDGE_LEFT, 1);
        layer::gtk_layer_set_exclusive_zone(ptr, 0);
        layer::gtk_layer_set_keyboard_mode(ptr, layer::KEYBOARD_NONE);
    }
    // WebKitGTK in a freshly mapped layer surface never paints its first frame (see make_non_activating): unmap and map it once, right after the first map.
    let remapped = std::cell::Cell::new(false);
    gw.connect_map_event(move |w, _| {
        apply_rects(w, &DESKTOP_REGION.lock().unwrap());
        if !remapped.replace(true) {
            let w = w.clone();
            gtk::glib::idle_add_local_once(move || {
                w.hide();
                w.show_all();
                apply_rects(&w, &DESKTOP_REGION.lock().unwrap());
            });
        }
        gtk::glib::Propagation::Proceed
    });
    DESKTOP_LAYER.store(true, Ordering::Relaxed);
    crate::log::line("desktop cat is a layer-shell surface");
}

/// Whether the app can put the desktop cat's window where it wants: a layer-shell surface (margins), or any window on X11. GNOME's Wayland session ignores a window's position, so
/// there the cat's spot is not ours to set or to remember, and Settings says so under the switch. NOTCHMEOW_DESKTOP_POSITION=1 or 0 overrides the guess.
pub fn desktop_positioned() -> bool {
    match std::env::var("NOTCHMEOW_DESKTOP_POSITION").as_deref() {
        Ok("1") => return true,
        Ok("0") => return false,
        _ => {}
    }
    DESKTOP_LAYER.load(Ordering::Relaxed) || std::env::var_os("WAYLAND_DISPLAY").is_none()
}

/// Puts the desktop window's top-left at (x, y) physical px: the margins of a layer surface on the monitor's output, or the window's position.
pub fn place_desktop(win: &WebviewWindow, x: i32, y: i32, monitor_index: usize, monitor_origin: (i32, i32), scale: f64) {
    if !DESKTOP_LAYER.load(Ordering::Relaxed) {
        let _ = win.set_position(tauri::PhysicalPosition::new(x, y));
        return;
    }
    let Ok(gw) = win.gtk_window() else { return };
    let ptr = gtk_window_ptr(&gw);
    let s = if scale > 0.0 { scale } else { 1.0 };
    unsafe {
        if DESKTOP_MONITOR.swap(monitor_index, Ordering::Relaxed) != monitor_index {
            // tao lists the monitors in GDK's order, so the index is the same one.
            if let Some(m) = gtk::gdk::Display::default().and_then(|d| d.monitor(monitor_index as i32)) {
                layer::gtk_layer_set_monitor(ptr, m.to_glib_none().0);
            }
        }
        layer::gtk_layer_set_margin(ptr, layer::EDGE_LEFT, ((x - monitor_origin.0) as f64 / s).round() as std::os::raw::c_int);
        layer::gtk_layer_set_margin(ptr, layer::EDGE_TOP, ((y - monitor_origin.1) as f64 / s).round() as std::os::raw::c_int);
    }
}

/// Only these rectangles (window logical px) take the mouse; everything else goes to the window underneath.
pub fn set_desktop_input(win: &WebviewWindow, rects: &[(f64, f64, f64, f64)]) {
    *DESKTOP_REGION.lock().unwrap() = rects.to_vec();
    let Ok(gw) = win.gtk_window() else { return };
    apply_rects(&gw, rects);
}

fn apply_rects(gw: &impl IsA<gtk::Widget>, rects: &[(f64, f64, f64, f64)]) {
    let Some(gdk_window) = gw.window() else { return };
    let region = gtk::cairo::Region::create();
    for &(x, y, w, h) in rects {
        let _ = region.union_rectangle(&gtk::cairo::RectangleInt::new(x.floor() as i32, y.floor() as i32, w.ceil() as i32, h.ceil() as i32));
    }
    gdk_window.input_shape_combine_region(&region, 0, 0);
}

/// GTK's double-click time in ms.
pub fn double_click_ms() -> Option<u32> {
    gtk::Settings::default().map(|s| s.gtk_double_click_time().max(0) as u32)
}

const LOGIN1: &str = "org.freedesktop.login1";
const LOGIN1_SESSION: &str = "org.freedesktop.login1.Session";

// What comes off the system bus is data from any process that can send a signal, so every reader below checks the shape first and answers None for anything else: glib's
// `child_value` and `VariantDict::new` assert, and a panic inside a gio callback aborts the app.

/// The new `LockedHint` in a `PropertiesChanged` body `(s, a{sv}, as)` (interface, changed properties, invalidated names), when it is one of the changed ones.
fn locked_hint_changed(params: &gtk::glib::Variant) -> Option<bool> {
    if params.type_().as_str() != "(sa{sv}as)" {
        return None;
    }
    let changed = params.try_child_value(1)?.get::<gtk::glib::VariantDict>()?;
    changed.lookup::<bool>("LockedHint").ok().flatten()
}

/// The new `Active` in a `PropertiesChanged` body, by the same reading as `locked_hint_changed`: false when the user has switched to another session (another user, another virtual terminal).
fn active_changed(params: &gtk::glib::Variant) -> Option<bool> {
    if params.type_().as_str() != "(sa{sv}as)" {
        return None;
    }
    let changed = params.try_child_value(1)?.get::<gtk::glib::VariantDict>()?;
    changed.lookup::<bool>("Active").ok().flatten()
}

/// A `PrepareForSleep` body `(b)`: true just before the machine sleeps, false when it is back. A body of any other shape is None, "no news": reading it as false would
/// clear a real away state.
fn prepare_for_sleep(params: &gtk::glib::Variant) -> Option<bool> {
    if params.type_().as_str() != "(b)" {
        return None;
    }
    params.try_child_value(0)?.get::<bool>()
}

/// The object path in a `GetSessionByPID` reply `(o)`.
fn session_path(reply: &gtk::glib::Variant) -> Option<String> {
    if reply.type_().as_str() != "(o)" {
        return None;
    }
    let child = reply.try_child_value(0)?;
    let path = child.str()?;
    gtk::glib::Variant::is_object_path(path).then(|| path.to_owned())
}

/// The value in a `Properties.Get` reply `(v)` for a boolean property.
fn locked_hint_value(reply: &gtk::glib::Variant) -> Option<bool> {
    if reply.type_().as_str() != "(v)" {
        return None;
    }
    reply.try_child_value(0)?.as_variant()?.get::<bool>()
}

/// Lock, unlock and suspend from logind, over the system bus through gio (nothing polls): `notify(Off, true)` just before the machine sleeps and `false` when it is back,
/// `notify(Locked, on)` when the session locks or unlocks. Desktops lock through the session's `LockedHint` property and do not always emit `Lock`, so this process's own session
/// (`GetSessionByPID`) is asked for its `LockedHint` once and watched through `PropertiesChanged`. Where logind or the session is not there the page's own visibility still hides
/// the cat. Must be called on the GTK main thread (the setup is); nothing here blocks it.
pub fn watch_away(notify: impl Fn(AwaySource, bool) + Send + Sync + 'static) {
    use gtk::gio;
    use gtk::glib::{self, ToVariant};
    let notify: std::sync::Arc<dyn Fn(AwaySource, bool) + Send + Sync> = std::sync::Arc::new(notify);
    gio::bus_get(gio::BusType::System, gio::Cancellable::NONE, move |conn| {
        let Ok(conn) = conn else { return };
        let n = notify.clone();
        let _ = conn.signal_subscribe(
            Some(LOGIN1), Some("org.freedesktop.login1.Manager"), Some("PrepareForSleep"), Some("/org/freedesktop/login1"), None, gio::DBusSignalFlags::NONE,
            move |_, _, _, _, _, params| {
                if let Some(off) = prepare_for_sleep(params) {
                    n(AwaySource::Off, off);
                }
            },
        );
        let c = conn.clone();
        conn.call(
            Some(LOGIN1), "/org/freedesktop/login1", "org.freedesktop.login1.Manager", "GetSessionByPID", Some(&(std::process::id(),).to_variant()),
            glib::VariantTy::new("(o)").ok(), gio::DBusCallFlags::NONE, -1, gio::Cancellable::NONE,
            move |reply| {
                let path = reply.ok().and_then(|r| session_path(&r));
                watch_session(&c, &notify, path.as_deref());
            },
        );
    });
}

/// The session's `LockedHint` (`Properties.Get`), asked of logind and handed to `done` when the answer is in: None when it cannot be read. Nothing blocks.
fn read_locked_hint(conn: &gtk::gio::DBusConnection, path: &str, done: impl FnOnce(Option<bool>) + 'static) {
    use gtk::glib::{self, ToVariant};
    use gtk::gio;
    conn.call(
        Some(LOGIN1), path, "org.freedesktop.DBus.Properties", "Get", Some(&(LOGIN1_SESSION, "LockedHint").to_variant()),
        glib::VariantTy::new("(v)").ok(), gio::DBusCallFlags::NONE, -1, gio::Cancellable::NONE,
        move |reply| done(reply.ok().and_then(|r| locked_hint_value(&r))),
    );
}

/// The session's `Lock` and `Unlock` and, for `path` (this process's own session), its `LockedHint`. Without a path (no logind session for this process: a service, a
/// container) only `Lock` and `Unlock` are watched, from every session on the bus: a lock of someone else's session then also hides the cat.
fn watch_session(conn: &gtk::gio::DBusConnection, notify: &std::sync::Arc<dyn Fn(AwaySource, bool) + Send + Sync>, path: Option<&str>) {
    use gtk::gio;
    for (signal, away) in [("Lock", true), ("Unlock", false)] {
        let n = notify.clone();
        let _ = conn.signal_subscribe(
            Some(LOGIN1), Some(LOGIN1_SESSION), Some(signal), path, None, gio::DBusSignalFlags::NONE,
            move |_, _, _, _, _, _| n(AwaySource::Locked, away),
        );
    }
    let Some(path) = path else { return };
    let n = notify.clone();
    let session = path.to_owned();
    let _ = conn.signal_subscribe(
        Some(LOGIN1), Some("org.freedesktop.DBus.Properties"), Some("PropertiesChanged"), Some(path), Some(LOGIN1_SESSION), gio::DBusSignalFlags::NONE,
        move |conn, _, _, _, _, params| {
            if let Some(on) = locked_hint_changed(params) {
                n(AwaySource::Locked, on);
            }
            // A switch to another user's session is away as a lock is (the same cause: the session is not the one in front).
            match active_changed(params) {
                Some(false) => n(AwaySource::Locked, true),
                // Switching back shows the lock screen when the session is still locked: the unlock is told only when the session is known not to be (a late return, never an early one).
                Some(true) => {
                    let n = n.clone();
                    read_locked_hint(conn, &session, move |locked| {
                        if unlock_is_real(locked) {
                            n(AwaySource::Locked, false);
                        }
                    });
                }
                None => {}
            }
        },
    );
    // Subscribed first, read after: a change in between is not lost. A session that starts locked is reported as locked.
    let n = notify.clone();
    read_locked_hint(conn, path, move |locked| {
        if locked == Some(true) {
            n(AwaySource::Locked, true);
        }
    });
}

/// Nothing to look for: the cat's layer is below fullscreen windows already.
pub fn fullscreen_app_covers(_monitors: &[(i32, i32, u32, u32)]) -> bool {
    false
}

/// Puts `text` on the clipboard (a path the user dropped on an agent's cat: the Sidekick copies it so they can paste it into that agent). The clipboard is the GTK main thread's, so the
/// work is handed to it; True when it was handed over. Nothing is pasted anywhere. (On a Wayland desktop a program that was not given the keyboard focus may be refused by the
/// compositor; the line the island shows after a drop says so when the copy did not happen.)
pub fn copy_text(app: &AppHandle, text: &str) -> bool {
    let text = text.to_string();
    app.run_on_main_thread(move || {
        let clipboard = gtk::Clipboard::get(&gtk::gdk::SELECTION_CLIPBOARD);
        clipboard.set_text(&text);
        clipboard.store();
    })
    .is_ok()
}

/// Seconds since the user's last input, from GNOME's idle monitor (Mutter, over the session bus), or None where there is none (KDE, wlroots, a session with no `gdbus`): the
/// Sidekick then counts only a lock or a sleep as away. It asks through `gdbus`, a program of glib that GNOME desktops have, with a one second limit; the Sidekick calls it when a
/// hook event comes, when the island opens and on an unlock, never on a timer.
pub fn idle_seconds() -> Option<u64> {
    let gdbus = find_on_path("gdbus")?;
    let out = Command::new(gdbus)
        .args([
            "call", "--session", "--timeout", "1", "--dest", "org.gnome.Mutter.IdleMonitor", "--object-path", "/org/gnome/Mutter/IdleMonitor/Core",
            "--method", "org.gnome.Mutter.IdleMonitor.GetIdletime",
        ])
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    crate::sidekick_presence::parse_idle_ms(&String::from_utf8_lossy(&out.stdout)).map(|ms| ms / 1000)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_properties_changed_that_carries_the_locked_hint_is_read_and_one_that_does_not_is_not() {
        use gtk::glib::{self, ToVariant};
        let signal = |entries: &[(&str, bool)]| {
            let d = glib::VariantDict::new(None);
            for (k, v) in entries {
                d.insert(k, *v);
            }
            glib::Variant::tuple_from_iter([LOGIN1_SESSION.to_variant(), d.end(), Vec::<String>::new().to_variant()])
        };
        assert_eq!(locked_hint_changed(&signal(&[("LockedHint", true)])), Some(true));
        assert_eq!(locked_hint_changed(&signal(&[("IdleHint", true), ("LockedHint", false)])), Some(false));
        assert_eq!(locked_hint_changed(&signal(&[("IdleHint", true)])), None, "another property changed");
        assert_eq!(locked_hint_changed(&true.to_variant()), None, "not a PropertiesChanged at all");
    }

    #[test]
    fn a_properties_changed_of_the_wrong_shape_is_no_news_and_never_a_panic() {
        use gtk::glib::{self, ToVariant};
        let tuple = |children: Vec<glib::Variant>| glib::Variant::tuple_from_iter(children);
        let none: Vec<glib::Variant> = Vec::new();
        assert_eq!(locked_hint_changed(&"LockedHint".to_variant()), None, "a string");
        assert_eq!(locked_hint_changed(&tuple(none)), None, "an empty tuple");
        assert_eq!(locked_hint_changed(&tuple(vec![LOGIN1_SESSION.to_variant(), true.to_variant(), Vec::<String>::new().to_variant()])), None, "(s,b,as) instead of (s,a{{sv}},as)");
        let strings = glib::VariantDict::new(None);
        strings.insert("LockedHint", "yes");
        let typed = tuple(vec![LOGIN1_SESSION.to_variant(), strings.end(), Vec::<String>::new().to_variant()]);
        assert_eq!(locked_hint_changed(&typed), None, "LockedHint of the wrong type");
        let mut plain = std::collections::HashMap::new();
        plain.insert("LockedHint".to_string(), "yes".to_string());
        assert_eq!(locked_hint_changed(&tuple(vec![LOGIN1_SESSION.to_variant(), plain.to_variant(), Vec::<String>::new().to_variant()])), None, "(s,a{{ss}},as)");
        assert_eq!(locked_hint_changed(&tuple(vec![LOGIN1_SESSION.to_variant()])), None, "too short");
    }

    #[test]
    fn a_prepare_for_sleep_is_read_and_a_malformed_one_is_no_news_not_false() {
        use gtk::glib::{self, ToVariant};
        let tuple = |children: Vec<glib::Variant>| glib::Variant::tuple_from_iter(children);
        assert_eq!(prepare_for_sleep(&tuple(vec![true.to_variant()])), Some(true), "going to sleep");
        assert_eq!(prepare_for_sleep(&tuple(vec![false.to_variant()])), Some(false), "back");
        assert_eq!(prepare_for_sleep(&true.to_variant()), None, "a bare bool is no tuple");
        assert_eq!(prepare_for_sleep(&"true".to_variant()), None, "a string");
        assert_eq!(prepare_for_sleep(&tuple(Vec::new())), None, "an empty tuple");
        assert_eq!(prepare_for_sleep(&tuple(vec!["true".to_variant()])), None, "a string payload");
        assert_eq!(prepare_for_sleep(&tuple(vec![1u32.to_variant()])), None, "a number payload");
        assert_eq!(prepare_for_sleep(&tuple(vec![true.to_variant(), false.to_variant()])), None, "two payloads");
    }

    #[test]
    fn the_session_path_and_the_initial_locked_hint_are_read_from_their_replies_and_nothing_else() {
        use gtk::glib::{self, ToVariant};
        let tuple = |children: Vec<glib::Variant>| glib::Variant::tuple_from_iter(children);
        let path = |s: &str| glib::variant::ObjectPath::try_from(s.to_string()).unwrap().to_variant();
        assert_eq!(session_path(&tuple(vec![path("/org/freedesktop/login1/session/_32")])).as_deref(), Some("/org/freedesktop/login1/session/_32"));
        assert_eq!(session_path(&tuple(vec!["/org/freedesktop/login1/session/_32".to_variant()])), None, "a string is not an object path");
        assert_eq!(session_path(&tuple(Vec::new())), None, "an empty reply");
        assert_eq!(session_path(&path("/x").to_variant()), None, "no tuple");
        assert_eq!(session_path(&tuple(vec![true.to_variant()])), None, "not a string");

        let boxed = |v: glib::Variant| tuple(vec![glib::Variant::from_variant(&v)]);
        assert_eq!(locked_hint_value(&boxed(true.to_variant())), Some(true));
        assert_eq!(locked_hint_value(&boxed(false.to_variant())), Some(false));
        assert_eq!(locked_hint_value(&boxed("true".to_variant())), None, "a boxed string");
        assert_eq!(locked_hint_value(&tuple(vec![true.to_variant()])), None, "not boxed");
        assert_eq!(locked_hint_value(&tuple(Vec::new())), None, "an empty reply");
        assert_eq!(locked_hint_value(&"x".to_variant()), None, "a string");
    }

    #[test]
    fn only_a_private_directory_of_ours_can_hold_the_relay_socket() {
        let base = std::env::temp_dir().join(format!("notchmeow-rt-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&base);
        let dir = base.join("runtime");
        std::fs::create_dir_all(&dir).unwrap();
        let set = |mode| std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(mode)).unwrap();

        set(0o700);
        assert!(is_private_dir(&dir));

        // Readable or reachable by group or others: no.
        for open in [0o750, 0o705, 0o755, 0o777, 0o1777] {
            set(open);
            assert!(!is_private_dir(&dir), "{open:o} must be refused");
        }

        // A symlink to a private directory: no, the link itself is what we got.
        set(0o700);
        let link = base.join("link");
        std::os::unix::fs::symlink(&dir, &link).unwrap();
        assert!(!is_private_dir(&link));

        // Missing: no.
        assert!(!is_private_dir(&base.join("missing")));

        let _ = std::fs::remove_dir_all(&base);
    }

    #[test]
    fn private_dirs_are_closed_to_everyone_else() {
        use std::os::unix::fs::MetadataExt;
        let dir = std::env::temp_dir().join(format!("notchmeow-priv-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(0o755)).unwrap();
        ensure_private_dir(&dir).unwrap();
        assert_eq!(std::fs::metadata(&dir).unwrap().mode() & 0o777, 0o700);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
