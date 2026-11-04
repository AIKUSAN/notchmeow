// The desktop cat's window (sub-project H, spec §3): a second transparent, borderless, always-on-top window that holds the big cat while it lives on the desktop. The page in it
// (src/desktop/body.ts) draws the cat; the island's page (src/island/desktop.ts) runs the trip. This file only moves the window and decides what takes the mouse:
//   * the window is created hidden at launch, before the island's webview (a WebView2 window created later comes up blank, see lib.rs), and shown only while the cat is on the
//     desktop or in the air;
//   * click-through is the body's shape: on Windows a poll flips WS_EX_TRANSPARENT from the cursor, slowly while the cursor is far from the cat and at 60 Hz when it is near, and
//     only while the cat is out; on Linux the window's input region is the shape, and nothing polls the cursor (Wayland gives an app none);
//   * positions are in points, the contract's unit (cat/desktop.ts): physical pixels divided by the primary screen's scale factor, the origin at the top left of the main screen.
//     A window on a screen with another scale factor keeps the cat the size that screen gives it;
//   * a fullscreen app covering the cat's screen hides the window (Windows; on Linux the layer is below fullscreen windows by itself).

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::time::{Duration, Instant};

use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, Manager, Monitor, PhysicalSize, State, WebviewUrl, WebviewWindow, WebviewWindowBuilder};

use crate::platform;

pub const WINDOW_LABEL: &str = "desktop";

/// The mouse is let in this many logical px outside the body's circles, so a click is never swallowed at the edge.
const HIT_SLACK: f64 = 4.0;
/// The cursor poll runs at 60 Hz within this many logical px of the window, and at 10 Hz farther away.
const NEAR_PX: f64 = 90.0;
const NEAR_MS: u64 = 16;
const FAR_MS: u64 = 100;
/// The screens and a fullscreen app are looked at this often (ms) while the cat is out.
const CHECK_MS: u128 = 500;

#[derive(Serialize, Clone, Copy, Debug, PartialEq)]
pub struct Rect {
    pub x: f64,
    pub y: f64,
    pub w: f64,
    pub h: f64,
}

#[derive(Serialize)]
pub struct ScreenOut {
    pub frame: Rect,
    pub visible: Rect,
    pub main: bool,
}

/// What the page needs to know about the screens, in points (see the top of this file).
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct World {
    pub screens: Vec<ScreenOut>,
    /// The frame of the screen the island is on.
    pub island: Rect,
    /// The island screen's scale factor over the primary screen's.
    pub island_k: f64,
    /// The primary screen's scale factor: the unit of a point.
    pub scale: f64,
    /// False where the system places windows itself (GNOME): the cat's position is then not ours to set or to remember.
    pub positioned: bool,
}

#[derive(Serialize)]
pub struct Point {
    pub x: f64,
    pub y: f64,
}

/// A circle that takes the mouse, in window logical px.
#[derive(Deserialize, Clone, Copy, Debug, Default)]
pub struct Circle {
    pub x: f64,
    pub y: f64,
    pub r: f64,
}

#[derive(Default)]
struct Placed {
    /// The window's logical size, and the head's centre in it.
    w: f64,
    h: f64,
    head_x: f64,
    head_y: f64,
    shapes: Vec<Circle>,
    /// Where the head's centre is, in points; None before the first placement.
    spot: Option<(f64, f64)>,
    /// The scale factor of the screen the window is on.
    scale: f64,
}

/// What the commands and the poll thread share about the desktop window.
pub struct Gate {
    /// What the poll thread waits on (`cv`): the window wanted, and what the platform says about the session. One lock, so a wake-up is never lost.
    run: Mutex<Run>,
    cv: Condvar,
    placed: Mutex<Placed>,
    /// The page wants the window shown, and a fullscreen app covers it: shown means both.
    wanted: AtomicBool,
    covered: AtomicBool,
    /// The cat is carried by the pointer: the whole window takes the mouse.
    dragging: AtomicBool,
    /// The cat is awake and drawn: shown, not asleep, not away, page visible. The page says so; the poll's light checks run only then.
    awake: AtomicBool,
    /// Mirrors the window flag so the OS is only called when it changes.
    ignoring: AtomicBool,
}

pub type DesktopGate = Arc<Gate>;

impl Gate {
    pub fn new() -> Self {
        Self {
            run: Mutex::new(Run { active: false, away: AwayState::default() }),
            cv: Condvar::new(),
            placed: Mutex::new(Placed { scale: 1.0, ..Default::default() }),
            wanted: AtomicBool::new(false),
            covered: AtomicBool::new(false),
            dragging: AtomicBool::new(false),
            awake: AtomicBool::new(false),
            ignoring: AtomicBool::new(true),
        }
    }

    fn set_active(&self, on: bool) {
        let mut g = self.run.lock().unwrap();
        g.active = on;
        self.cv.notify_all();
    }

    /// One platform watcher's news (a lock or an unlock, the display or the machine off or on). Returns the combined away flag when it changed, and wakes the poll then.
    fn report_away(&self, source: AwaySource, on: bool) -> Option<bool> {
        let mut g = self.run.lock().unwrap();
        let changed = match source {
            AwaySource::Locked => g.away.set_locked(on),
            AwaySource::Off => g.away.set_off(on),
        };
        if changed.is_some() {
            self.cv.notify_all();
        }
        changed
    }

    fn is_away(&self) -> bool {
        self.run.lock().unwrap().away.away()
    }

    /// Blocks while the poll has nothing to do: the cat is home (no window wanted) or the session is away (locked, or the display off).
    fn wait_until_running(&self) {
        let mut g = self.run.lock().unwrap();
        while parked(g.active, g.away.away()) {
            g = self.cv.wait(g).unwrap();
        }
    }

    fn is_running(&self) -> bool {
        let g = self.run.lock().unwrap();
        !parked(g.active, g.away.away())
    }

    /// The window is wanted (shown or not, away or not).
    fn is_active(&self) -> bool {
        self.run.lock().unwrap().active
    }
}

struct Run {
    active: bool,
    away: AwayState,
}

/// What a platform watcher reports: the session was locked or unlocked, or the display (or the machine, on Linux) went off or on.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum AwaySource {
    Locked,
    Off,
}

/// Away is "locked or off": two causes, one flag each, so the end of one never ends the other (the display woken at the lock screen is still a locked session).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct AwayState {
    locked: bool,
    off: bool,
}

impl AwayState {
    pub fn away(&self) -> bool {
        self.locked || self.off
    }

    /// The new combined flag, only when it changed.
    pub fn set_locked(&mut self, on: bool) -> Option<bool> {
        let was = self.away();
        self.locked = on;
        (self.away() != was).then(|| self.away())
    }

    pub fn set_off(&mut self, on: bool) -> Option<bool> {
        let was = self.away();
        self.off = on;
        (self.away() != was).then(|| self.away())
    }
}

/// The console display state of a power-setting notification: 0 off, 1 on, 2 dimmed. Off and on are news; dimmed (or anything else) changes nothing.
#[cfg_attr(not(windows), allow(dead_code))]
pub fn display_away(state: u8) -> Option<bool> {
    match state {
        0 => Some(true),
        1 => Some(false),
        _ => None,
    }
}

/// The poll thread sleeps on its condvar (no wake-ups at all) while the cat is home or the session is away.
pub fn parked(active: bool, away: bool) -> bool {
    !active || away
}

// ── Pure helpers (tested) ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────

/// True when (x, y), in window logical px, is on one of the circles, `slack` px wider.
pub fn hits(shapes: &[Circle], x: f64, y: f64, slack: f64) -> bool {
    shapes.iter().any(|c| (x - c.x).hypot(y - c.y) <= c.r + slack)
}

/// A physical rectangle as points: every number divided by the primary screen's scale factor.
pub fn rect_in_points(pos: (i32, i32), size: (u32, u32), unit: f64) -> Rect {
    let s = if unit > 0.0 { unit } else { 1.0 };
    Rect { x: pos.0 as f64 / s, y: pos.1 as f64 / s, w: size.0 as f64 / s, h: size.1 as f64 / s }
}

/// The window's top-left in physical px so that the head's centre (`head`, in the window's logical px) is at `spot` (points): the spot is physical / `unit`, the head is
/// logical * `scale`, the scale factor of the screen the window is on.
pub fn window_origin(spot: (f64, f64), head: (f64, f64), unit: f64, scale: f64) -> (i32, i32) {
    ((spot.0 * unit - head.0 * scale).round() as i32, (spot.1 * unit - head.1 * scale).round() as i32)
}

/// The circle (plus `slack` px, the radius `hits` uses) as one-logical-px-tall rows `(x, y, w, h)`, for an input region that is the cat's shape and not the squares around it
/// (spec §2: "the head circle plus the badge and kitten slots"). Row `y` spans the circle at its centre line, `y + 0.5`, so a point on a row's centre line is covered
/// exactly when `hits` says it is. Only rows inside a window (0..4000 px, what `desktop_layout` accepts) are made.
pub fn circle_rows(c: &Circle, slack: f64) -> Vec<(f64, f64, f64, f64)> {
    let r = c.r + slack;
    if !(r >= 0.0) || !c.x.is_finite() || !c.y.is_finite() {
        return Vec::new();
    }
    let (top, bottom) = ((c.y - r).floor().max(0.0), (c.y + r).ceil().min(4000.0));
    let mut rows = Vec::new();
    let mut y = top;
    while y < bottom {
        let dy = y + 0.5 - c.y;
        let sq = r * r - dy * dy;
        if sq >= 0.0 {
            let half = sq.sqrt();
            rows.push((c.x - half, y, 2.0 * half, 1.0));
        }
        y += 1.0;
    }
    rows
}

/// How long the cursor poll sleeps: 16 ms when the cursor is within 90 logical px of the window, else 100 ms.
pub fn poll_ms(lx: f64, ly: f64, w: f64, h: f64) -> u64 {
    if lx > -NEAR_PX && lx < w + NEAR_PX && ly > -NEAR_PX && ly < h + NEAR_PX { NEAR_MS } else { FAR_MS }
}

fn same_monitor(a: &Monitor, b: &Monitor) -> bool {
    a.position() == b.position() && a.size() == b.size()
}

// ── Screens ───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

/// The primary screen's scale factor, the unit of a point.
fn unit(app: &AppHandle) -> f64 {
    app.primary_monitor().ok().flatten().map(|m| m.scale_factor()).filter(|s| *s > 0.0).unwrap_or(1.0)
}

fn frame_of(m: &Monitor, u: f64) -> Rect {
    rect_in_points((m.position().x, m.position().y), (m.size().width, m.size().height), u)
}

fn visible_of(m: &Monitor, u: f64) -> Rect {
    let a = m.work_area();
    rect_in_points((a.position.x, a.position.y), (a.size.width, a.size.height), u)
}

pub fn world(app: &AppHandle, pref: &str) -> World {
    let u = unit(app);
    let primary = app.primary_monitor().ok().flatten();
    let monitors = app.available_monitors().unwrap_or_default();
    let screens: Vec<ScreenOut> = monitors
        .iter()
        .map(|m| ScreenOut { frame: frame_of(m, u), visible: visible_of(m, u), main: primary.as_ref().is_some_and(|p| same_monitor(p, m)) })
        .collect();
    let island = crate::island::target_monitor(app, pref);
    let (island_rect, island_k) = match &island {
        Some(m) => (frame_of(m, u), m.scale_factor() / u),
        None => (Rect { x: 0.0, y: 0.0, w: 1920.0, h: 1080.0 }, 1.0),
    };
    World { screens, island: island_rect, island_k, scale: u, positioned: platform::desktop_positioned() }
}

/// The monitor that holds `spot` (points) and its index, else the primary one.
fn monitor_for(app: &AppHandle, spot: (f64, f64)) -> Option<(usize, Monitor)> {
    let u = unit(app);
    let list = app.available_monitors().ok()?;
    let held = |m: &Monitor| {
        let r = frame_of(m, u);
        spot.0 >= r.x && spot.0 < r.x + r.w && spot.1 >= r.y && spot.1 < r.y + r.h
    };
    let index = list.iter().position(held).or_else(|| {
        let p = app.primary_monitor().ok().flatten()?;
        list.iter().position(|m| same_monitor(&p, m))
    })?;
    Some((index, list[index].clone()))
}

/// The arrangement of screens, as a string: a change means the spot has to be found again.
fn screens_key(app: &AppHandle) -> String {
    let mut parts: Vec<String> = app
        .available_monitors()
        .unwrap_or_default()
        .iter()
        .map(|m| format!("{},{},{},{},{}", m.position().x, m.position().y, m.size().width, m.size().height, m.scale_factor().to_bits()))
        .collect();
    parts.sort();
    parts.join("|")
}

// ── The window ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

pub fn window(app: &AppHandle) -> Option<WebviewWindow> {
    app.get_webview_window(WINDOW_LABEL)
}

/// In a dev build the page is served by Vite, so the window needs the absolute dev URL; a bundled build resolves it inside the app bundle.
fn page_url(app: &AppHandle) -> WebviewUrl {
    #[cfg(dev)]
    if let Some(mut base) = app.config().build.dev_url.clone() {
        base.set_path("/desktop.html");
        return WebviewUrl::External(base);
    }
    let _ = app;
    WebviewUrl::App("desktop.html".into())
}

/// Creates the desktop cat's window, hidden. It exists from launch on, so a cat that is out never has to wait for a webview to start (and a WebView2 window created later comes up
/// blank in this app, see lib.rs). Its page runs nothing while the window is hidden.
pub fn create_window(app: &AppHandle) {
    let builder = WebviewWindowBuilder::new(app, WINDOW_LABEL, page_url(app))
        .additional_browser_args(crate::BROWSER_ARGS)
        .title("NotchMeow cat")
        .inner_size(120.0, 160.0)
        .decorations(false)
        .transparent(true)
        .shadow(false)
        .always_on_top(true)
        .skip_taskbar(true)
        .resizable(false)
        .focused(false)
        .visible(false)
        .maximizable(false)
        .minimizable(false)
        .closable(false);
    // Tauri offers `drag_and_drop` on Windows only (it is the WS_EX_ACCEPTFILES switch of the window); a Linux window takes no file drop either, as nothing in its page listens for one.
    #[cfg(windows)]
    let builder = builder.drag_and_drop(false);
    #[cfg(target_os = "linux")]
    let builder = builder.focusable(false).visible_on_all_workspaces(true);
    match builder.build() {
        Ok(win) => platform::make_desktop_window(&win),
        Err(err) => crate::log::line(format!("desktop window failed: {err}")),
    }
}

/// Shown while the page wants it and nothing covers it.
fn apply_visibility(app: &AppHandle, gate: &Gate) {
    let Some(win) = window(app) else { return };
    let show = gate.wanted.load(Ordering::Relaxed) && !gate.covered.load(Ordering::Relaxed);
    if show {
        // Until the poll sees the cursor on the cat, nothing takes the mouse. (On Linux the input region is the shape and the flag stays off.)
        if platform::CURSOR_POLL {
            gate.ignoring.store(true, Ordering::Relaxed);
            let _ = win.set_ignore_cursor_events(true);
        }
        let _ = win.show();
        let _ = win.set_always_on_top(true);
    } else {
        let _ = win.hide();
    }
}

/// Puts the window where the head's centre is at `spot` (points), on the screen that holds it.
fn place(app: &AppHandle, gate: &Gate, x: f64, y: f64) {
    let Some(win) = window(app) else { return };
    let Some((index, m)) = monitor_for(app, (x, y)) else { return };
    let (u, s2) = (unit(app), m.scale_factor());
    let (head, size, rescale) = {
        let mut p = gate.placed.lock().unwrap();
        let rescale = (p.scale - s2).abs() > 1e-9;
        p.scale = s2;
        p.spot = Some((x, y));
        ((p.head_x, p.head_y), (p.w, p.h), rescale)
    };
    if rescale && size.0 > 0.0 {
        let _ = win.set_size(PhysicalSize::new((size.0 * s2).round().max(1.0) as u32, (size.1 * s2).round().max(1.0) as u32));
    }
    let (px, py) = window_origin((x, y), head, u, s2);
    platform::place_desktop(&win, px, py, index, (m.position().x, m.position().y), s2);
}

// ── Commands ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

#[tauri::command]
pub fn desktop_screens(app: AppHandle, shared: State<crate::Shared>) -> World {
    let pref = shared.settings.lock().unwrap().screen.clone();
    world(&app, &pref)
}

/// The page's size and what takes the mouse changed (a size picked, a kitten came): the window is resized, and put back so the head stays where it was.
#[tauri::command]
pub fn desktop_layout(app: AppHandle, gate: State<DesktopGate>, w: f64, h: f64, head_x: f64, head_y: f64, shapes: Vec<Circle>) {
    if !(w.is_finite() && h.is_finite() && head_x.is_finite() && head_y.is_finite()) || w < 1.0 || h < 1.0 || w > 4000.0 || h > 4000.0 {
        return;
    }
    let shapes: Vec<Circle> = shapes.into_iter().filter(|c| c.x.is_finite() && c.y.is_finite() && c.r.is_finite() && c.r >= 0.0).take(32).collect();
    let (s2, spot) = {
        let mut p = gate.placed.lock().unwrap();
        p.w = w;
        p.h = h;
        p.head_x = head_x;
        p.head_y = head_y;
        p.shapes = shapes.clone();
        (p.scale, p.spot)
    };
    let Some(win) = window(&app) else { return };
    // GTK never sizes a non-resizable window below its natural size: ask for resizable just before the resize (as island.rs does).
    #[cfg(target_os = "linux")]
    let _ = win.set_resizable(true);
    let _ = win.set_size(PhysicalSize::new((w * s2).round().max(1.0) as u32, (h * s2).round().max(1.0) as u32));
    // The input region is the shapes themselves, as rows: a bounding square would let the mouse in at its corners, outside the cat (Windows tests the circles with `hits`).
    let rects: Vec<(f64, f64, f64, f64)> = shapes.iter().flat_map(|c| circle_rows(c, HIT_SLACK)).collect();
    platform::set_desktop_input(&win, &rects);
    if let Some((x, y)) = spot {
        place(&app, &gate, x, y);
    }
}

#[tauri::command]
pub fn desktop_place(app: AppHandle, gate: State<DesktopGate>, x: f64, y: f64) {
    if x.is_finite() && y.is_finite() && x.abs() < 1e6 && y.abs() < 1e6 {
        place(&app, &gate, x, y);
    }
}

#[tauri::command]
pub fn desktop_show(app: AppHandle, gate: State<DesktopGate>, visible: bool) {
    gate.wanted.store(visible, Ordering::Relaxed);
    apply_visibility(&app, &gate);
    gate.set_active(visible);
    // A session that was already locked at launch was reported before the page listened: say so again when the cat is shown.
    if visible && gate.is_away() {
        let _ = app.emit_to(WINDOW_LABEL, "desktop-msg", serde_json::json!({ "k": "away", "on": true }));
    }
}

/// A platform watcher's news (see `AwaySource`): the page is told the combined state when it changed, and the poll parks or resumes with it.
pub fn away_changed(app: &AppHandle, gate: &Gate, source: AwaySource, on: bool) {
    if let Some(away) = gate.report_away(source, on) {
        let _ = app.emit_to(WINDOW_LABEL, "desktop-msg", serde_json::json!({ "k": "away", "on": away }));
    }
}

#[tauri::command]
pub fn desktop_drag(app: AppHandle, gate: State<DesktopGate>, on: bool) {
    gate.dragging.store(on, Ordering::Relaxed);
    if on && platform::CURSOR_POLL {
        gate.ignoring.store(false, Ordering::Relaxed);
        if let Some(win) = window(&app) {
            let _ = win.set_ignore_cursor_events(false);
        }
    }
}

/// The page says whether the cat is awake and drawn. Only then does the poll look at the screens and for a fullscreen app (twice a second), except while a fullscreen app covers
/// the cat: that check is what ends the covering.
#[tauri::command]
pub fn desktop_awake(gate: State<DesktopGate>, on: bool) {
    gate.awake.store(on, Ordering::Relaxed);
}

/// The system's double-click time in ms, or None where the app cannot read it: the page then waits 500 ms.
#[tauri::command]
pub fn desktop_double_click_ms() -> Option<u32> {
    platform::double_click_ms()
}

#[tauri::command]
pub fn desktop_native_drag(app: AppHandle) {
    if let Some(win) = window(&app) {
        let _ = win.start_dragging();
    }
}

#[tauri::command]
pub fn desktop_cursor(app: AppHandle) -> Option<Point> {
    let u = unit(&app);
    platform::cursor_physical().map(|(x, y)| Point { x: x / u, y: y / u })
}

/// A message between the island's page and the desktop page. Rust only forwards it, to the one window the label names.
#[tauri::command]
pub fn desktop_relay(app: AppHandle, to: String, msg: serde_json::Value) {
    let label = match to.as_str() {
        "island" => crate::island::WINDOW_LABEL,
        "desktop" => WINDOW_LABEL,
        _ => return,
    };
    let _ = app.emit_to(label, "desktop-msg", msg);
}

#[tauri::command]
pub fn desktop_menu_text(app: AppHandle, out: bool) {
    crate::tray::set_desktop_text(&app, out);
}

/// `WS_CAPTION` (`WS_BORDER | WS_DLGFRAME`): the style bits of a window that has a title bar.
#[cfg_attr(not(windows), allow(dead_code))]
pub const WS_CAPTION_BITS: u32 = 0x00C0_0000;

/// Whether the foreground window covers a whole monitor the way a fullscreen app does (physical px). A window with a title bar never counts, whatever its rectangle: a maximized
/// window's rectangle is the work area grown by its invisible 8 px frame, which is the whole monitor when the taskbar auto-hides or there is none. A real fullscreen or borderless
/// fullscreen window has no caption. The edges may be 1 px short of the monitor's.
#[cfg_attr(not(windows), allow(dead_code))]
pub fn covers_monitor(style: u32, rect: (i32, i32, i32, i32), monitors: &[(i32, i32, u32, u32)]) -> bool {
    if style & WS_CAPTION_BITS == WS_CAPTION_BITS {
        return false;
    }
    let (l, t, r, b) = (rect.0 as i64, rect.1 as i64, rect.2 as i64, rect.3 as i64);
    monitors.iter().any(|&(x, y, w, h)| {
        let (x, y, w, h) = (x as i64, y as i64, w as i64, h as i64);
        l <= x + 1 && t <= y + 1 && r >= x + w - 1 && b >= y + h - 1
    })
}

// ── The poll ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

/// Runs only while the cat is out and the session is here: parked on a condvar the rest of the time (at home, locked, display off), so those cost nothing. It flips click-through from
/// the cursor (Windows), tells the island's page when the screens changed, and hides the window under a fullscreen app.
pub fn spawn_poll(app: AppHandle, gate: DesktopGate) {
    std::thread::spawn(move || {
        let mut last_check = Instant::now();
        let mut covered = false;
        // What was seen last. A trip that ends starts the next one fresh; a lock or a display off keeps it, so a screen that came or went meanwhile is reported at the first check after.
        let mut last_screens: Option<String> = None;
        loop {
            gate.wait_until_running();
            let mut period = if platform::CURSOR_POLL { FAR_MS } else { CHECK_MS as u64 };
            while gate.is_running() {
                std::thread::sleep(Duration::from_millis(period));
                if last_check.elapsed().as_millis() >= CHECK_MS && (gate.awake.load(Ordering::Relaxed) || covered) {
                    last_check = Instant::now();
                    let key = screens_key(&app);
                    if last_screens.as_ref().is_some_and(|k| *k != key) {
                        let _ = app.emit_to(crate::island::WINDOW_LABEL, "desktop-msg", serde_json::json!({ "k": "screens" }));
                    }
                    last_screens = Some(key);
                    let rects: Vec<(i32, i32, u32, u32)> =
                        app.available_monitors().unwrap_or_default().iter().map(|m| (m.position().x, m.position().y, m.size().width, m.size().height)).collect();
                    let now = platform::fullscreen_app_covers(&rects);
                    if now != covered {
                        covered = now;
                        gate.covered.store(now, Ordering::Relaxed);
                        apply_visibility(&app, &gate);
                    }
                }
                if platform::CURSOR_POLL {
                    period = click_through(&app, &gate);
                }
            }
            if !gate.is_active() {
                last_screens = None;
            }
        }
    });
}

/// One look at the cursor: the window takes the mouse over the cat's shape (or while the cat is carried) and lets it through everywhere else. Returns how long to sleep.
fn click_through(app: &AppHandle, gate: &Gate) -> u64 {
    let Some(win) = window(app) else { return FAR_MS };
    let (Some((cx, cy)), Ok(origin)) = (platform::cursor_physical(), win.outer_position()) else { return FAR_MS };
    let (shapes, w, h, s2) = {
        let p = gate.placed.lock().unwrap();
        (p.shapes.clone(), p.w, p.h, if p.scale > 0.0 { p.scale } else { 1.0 })
    };
    let (lx, ly) = ((cx - origin.x as f64) / s2, (cy - origin.y as f64) / s2);
    let accept = gate.dragging.load(Ordering::Relaxed) || hits(&shapes, lx, ly, HIT_SLACK);
    if gate.ignoring.load(Ordering::Relaxed) == accept {
        gate.ignoring.store(!accept, Ordering::Relaxed);
        let _ = win.set_ignore_cursor_events(!accept);
    }
    poll_ms(lx, ly, w, h)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cat() -> Vec<Circle> {
        vec![Circle { x: 53.0, y: 90.0, r: 35.0 }, Circle { x: 90.0, y: 60.0, r: 8.0 }]
    }

    #[test]
    fn only_the_cat_takes_the_mouse() {
        let shapes = cat();
        assert!(hits(&shapes, 53.0, 90.0, 0.0), "the head");
        assert!(hits(&shapes, 90.0, 60.0, 0.0), "the badge");
        assert!(!hits(&shapes, 0.0, 0.0, 0.0), "a corner of the window passes through");
        assert!(!hits(&shapes, 53.0, 90.0 + 35.0 + 3.0, 0.0), "just outside the head");
        assert!(hits(&shapes, 53.0, 90.0 + 35.0 + 3.0, HIT_SLACK), "the slack lets the edge in");
        assert!(!hits(&[], 1.0, 1.0, HIT_SLACK), "no shapes, no mouse");
        assert!(!hits(&shapes, f64::NAN, 1.0, 0.0) && !hits(&shapes, 1.0, f64::INFINITY, 0.0), "a cursor that is not a number is on nothing");
    }

    #[test]
    fn a_physical_rectangle_is_in_points_and_the_window_goes_where_the_head_is() {
        assert_eq!(rect_in_points((1920, 0), (2560, 1440), 2.0), Rect { x: 960.0, y: 0.0, w: 1280.0, h: 720.0 });
        assert_eq!(rect_in_points((0, 0), (100, 100), 0.0), Rect { x: 0.0, y: 0.0, w: 100.0, h: 100.0 }, "a scale that is not positive is 1");
        // The head's centre (53, 90) in a window on a screen with scale 1.5, the unit 1.25: spot (400, 300) points is (500, 375) physical.
        assert_eq!(window_origin((400.0, 300.0), (53.0, 90.0), 1.25, 1.5), (421, 240));
        assert_eq!(window_origin((0.0, 0.0), (53.0, 90.0), 1.0, 1.0), (-53, -90), "the window may start off screen: the head is what is on it");
    }

    #[test]
    fn a_maximized_window_is_not_a_fullscreen_app_but_a_borderless_one_is() {
        // 1920x1080 monitor at the origin, a second one to its right.
        let monitors = [(0, 0, 1920u32, 1080u32), (1920, 0, 2560, 1440)];
        let (captioned, popup) = (0x11CF_0000u32, 0x9000_0000u32); // WS_OVERLAPPEDWINDOW|WS_VISIBLE|WS_MAXIMIZE, WS_POPUP|WS_VISIBLE
        assert_eq!(WS_CAPTION_BITS, 0x00C0_0000, "WS_CAPTION of the Win32 headers");
        // Maximized with the taskbar hidden: GetWindowRect is the monitor grown by 8 px on every side.
        assert!(!covers_monitor(captioned, (-8, -8, 1928, 1088), &monitors), "a maximized window has a title bar");
        assert!(covers_monitor(popup, (0, 0, 1920, 1080), &monitors), "borderless fullscreen");
        assert!(covers_monitor(popup, (1920, 0, 4480, 1440), &monitors), "on the second monitor");
        assert!(covers_monitor(popup, (-8, -8, 1928, 1088), &monitors), "a popup that overhangs still covers it");
        assert!(covers_monitor(popup, (1, 1, 1919, 1079), &monitors), "a pixel short at each edge still covers it");
        assert!(!covers_monitor(popup, (2, 0, 1920, 1080), &monitors), "two px short does not");
        assert!(!covers_monitor(popup, (0, 0, 1000, 700), &monitors), "a window smaller than the monitor");
        assert!(!covers_monitor(popup, (0, 0, 0, 0), &[]), "no monitors");
        assert!(covers_monitor(0, (0, 0, 1920, 1080), &monitors), "a style that could not be read counts by its rectangle");
    }

    #[test]
    fn the_cursor_poll_is_fast_only_near_the_window() {
        assert_eq!(poll_ms(50.0, 80.0, 110.0, 160.0), NEAR_MS, "over the window");
        assert_eq!(poll_ms(-50.0, 80.0, 110.0, 160.0), NEAR_MS, "just outside it");
        assert_eq!(poll_ms(-100.0, 80.0, 110.0, 160.0), FAR_MS);
        assert_eq!(poll_ms(300.0, 80.0, 110.0, 160.0), FAR_MS);
        assert_eq!(poll_ms(50.0, 400.0, 110.0, 160.0), FAR_MS);
    }

    /// True when the point is inside one of the rows, the way a region of those rectangles covers it.
    fn covered(rows: &[(f64, f64, f64, f64)], x: f64, y: f64) -> bool {
        rows.iter().any(|&(rx, ry, rw, rh)| x >= rx && x <= rx + rw && y >= ry && y < ry + rh)
    }

    #[test]
    fn the_input_region_is_the_circle_and_not_its_bounding_square() {
        let c = Circle { x: 53.0, y: 90.0, r: 35.0 };
        let big = c.r + HIT_SLACK;
        let rows = circle_rows(&c, HIT_SLACK);
        assert!(!rows.is_empty());
        for &(x, y, w, h) in &rows {
            assert!(x >= c.x - big - 1e-9 && x + w <= c.x + big + 1e-9 && y >= c.y - big - 1e-9 && y + h <= c.y + big + 1e-9, "a row {x},{y},{w},{h} is inside the bounding square");
            assert_eq!(h, 1.0, "one logical px tall");
        }
        let widest = rows.iter().map(|r| r.2).fold(0.0, f64::max);
        assert!((widest - 2.0 * big).abs() < 0.5, "the centre row is the full diameter, {widest}");
        assert!(!covered(&rows, c.x - big * 0.9, c.y - big * 0.9), "the corner of the square is not the cat");
        assert!(!covered(&rows, c.x + big * 0.9, c.y + big * 0.9), "the opposite corner either");
        assert!(covered(&rows, c.x + big * 0.5, c.y), "inside the circle");
        assert!(covered(&rows, c.x, c.y - big * 0.99), "the top of the circle");
        // At row-centre resolution the region and `hits` say the same for every point of a grid over the square.
        let mut y = c.y - big - 2.0;
        while y < c.y + big + 2.0 {
            let row_centre = y.floor() + 0.5;
            let mut x = c.x - big - 2.0;
            while x < c.x + big + 2.0 {
                assert_eq!(covered(&rows, x, row_centre), hits(&[c], x, row_centre, HIT_SLACK), "({x}, {row_centre})");
                x += 0.37;
            }
            y += 1.0;
        }
        assert!(circle_rows(&Circle { x: 5.0, y: 5.0, r: 0.0 }, 0.0).is_empty(), "a circle with no radius and no slack takes nothing");
    }

    #[test]
    fn a_lock_and_a_display_that_is_off_are_two_causes_and_only_changes_are_reported() {
        let mut a = AwayState::default();
        assert!(!a.away());
        assert_eq!(a.set_locked(true), Some(true), "the lock is the first cause");
        assert_eq!(a.set_off(true), None, "the display going off changes nothing: still away");
        assert_eq!(a.set_off(false), None, "the display woken at the lock screen: the session is still locked");
        assert!(a.away());
        assert_eq!(a.set_locked(false), Some(false), "the unlock ends it");
        assert_eq!(a.set_locked(false), None, "the same news twice is not news");
        assert!(!a.away());
    }

    #[test]
    fn a_resume_while_locked_stays_away_until_the_unlock() {
        let mut a = AwayState::default();
        assert_eq!(a.set_off(true), Some(true), "the machine sleeps");
        assert_eq!(a.set_locked(true), None, "locked on the way down");
        assert_eq!(a.set_off(false), None, "resumed, and still on the lock screen");
        assert!(a.away());
        assert_eq!(a.set_locked(false), Some(false), "unlocked: back");
        assert_eq!(a.set_off(true), Some(true), "and the display can go off again");
    }

    #[test]
    fn a_dimmed_display_is_not_news_and_only_off_and_on_are() {
        assert_eq!(display_away(0), Some(true), "off");
        assert_eq!(display_away(1), Some(false), "on");
        assert_eq!(display_away(2), None, "dimmed changes nothing");
        assert_eq!(display_away(7), None, "a state we do not know changes nothing");
    }

    #[test]
    fn the_poll_parks_at_home_and_while_away_and_runs_only_when_neither() {
        assert!(parked(false, false), "home");
        assert!(parked(false, true), "home and away");
        assert!(parked(true, true), "out, behind a lock screen or with the display off");
        assert!(!parked(true, false), "out and here");
    }

    #[test]
    fn the_gate_reports_the_combined_state_and_wakes_the_poll_only_when_it_changes() {
        let g = Gate::new();
        g.set_active(true);
        assert!(g.is_running());
        assert_eq!(g.report_away(AwaySource::Locked, true), Some(true));
        assert!(!g.is_running(), "away: the poll parks");
        assert!(g.is_away());
        assert_eq!(g.report_away(AwaySource::Off, true), None);
        assert_eq!(g.report_away(AwaySource::Off, false), None, "still locked");
        assert!(!g.is_running());
        assert_eq!(g.report_away(AwaySource::Locked, false), Some(false));
        assert!(g.is_running(), "back: the poll runs again");
    }
}
