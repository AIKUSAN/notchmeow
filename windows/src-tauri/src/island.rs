// Island window: placement on the chosen display, the two window sizes
// (full panel / invisible wake strip), click-through and the cursor poll.
//
// There is no notch on a PC, so the island is a black shape drawn at the top
// centre of the main display inside a borderless, transparent, always-on-top
// window that never takes focus.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::time::Duration;

use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager, Monitor, PhysicalPosition, PhysicalSize, WebviewWindow};

use crate::platform::{self, cursor_physical, left_button_down};
use crate::pointer::{ButtonEdges, Edge};

/// Logical size of the full window: the widest island and the tallest view, the chat at 560 px, with the corner below it. The twin is `PANEL_H` in `src/core/layout.ts`
/// (`scripts/companion-tests/size.test.mjs` holds them equal). The window is never the hit area: the island's own rect decides (`takes_mouse`, `click_region`).
pub const PANEL_W: f64 = 720.0;
pub const PANEL_H: f64 = 600.0;
/// While a mouse button is held, this much of the window (from its top) takes the mouse whole so a dragged file finds us (below). It is the window's height before the bigger chat
/// (320): a taller window must not swallow drops meant for what lies under it.
const DRAG_H: f64 = 320.0;
/// Logical size of the invisible strip that wakes the island when it is hidden.
pub const STRIP_W: f64 = 240.0;
pub const STRIP_H: f64 = 6.0;

pub const WINDOW_LABEL: &str = "island";

/// Margin around the island that still counts as "on the island", in logical px.
/// Wider than the macOS 6 pt because a click must never be swallowed.
const HIT_MARGIN: f64 = 14.0;

#[derive(Serialize, Clone)]
pub struct CursorPayload {
    pub x: f64,
    pub y: f64,
    /// Any mouse button is held (the wing's left-side dwell does not start, or starts over, while one is).
    pub down: bool,
}

/// A mouse button went down or came up while the page watches (the outside click). `x`, `y` are window-logical px like the cursor event; `own` (meaningful on a press) says the
/// window under the point belongs to this app (Settings, the desktop cat, the tray's menu): a click there is not outside the island.
#[derive(Serialize, Clone)]
pub struct ButtonPayload {
    pub down: bool,
    pub x: f64,
    pub y: f64,
    pub own: bool,
}

#[derive(Serialize, Clone)]
pub struct ScreenInfo {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
    pub scale: f64,
}

/// The island shape in window-logical coordinates, pushed by the front end.
/// The poll thread owns the click-through decision so it lands in the same 16 ms
/// tick as the cursor read — an IPC round trip here loses clicks.
#[derive(Clone, Copy, Default)]
pub struct IslandRect {
    pub x: f64,
    pub y: f64,
    pub w: f64,
    pub h: f64,
}

/// Wakes / parks the cursor poll thread so a hidden island costs literally nothing.
pub struct PollGate {
    active: Mutex<bool>,
    cv: Condvar,
    pub collapsed: AtomicBool,
    pub rect: Mutex<IslandRect>,
    /// Mirrors the window flag so we only call into the OS when it changes.
    ignoring: AtomicBool,
    /// The page sets this while the island is expanded: the poll then reads the mouse buttons on every tick and sends `pointer-button` for each edge (the outside click).
    pub watch_buttons: AtomicBool,
    /// The island's shape changed since the poll last looked: the click-through decision is made again even though the pointer has not moved (the wings folding).
    rect_dirty: AtomicBool,
}

impl PollGate {
    pub fn new() -> Self {
        Self {
            active: Mutex::new(false),
            cv: Condvar::new(),
            collapsed: AtomicBool::new(true),
            rect: Mutex::new(IslandRect::default()),
            ignoring: AtomicBool::new(false),
            watch_buttons: AtomicBool::new(false),
            rect_dirty: AtomicBool::new(false),
        }
    }

    pub fn set_rect(&self, rect: IslandRect) {
        *self.rect.lock().unwrap() = rect;
        self.rect_dirty.store(true, Ordering::Relaxed);
    }

    /// True once after each `set_rect`.
    pub fn take_rect_dirty(&self) -> bool {
        self.rect_dirty.swap(false, Ordering::Relaxed)
    }

    /// Forces the next poll tick to re-apply the flag (after a window resize).
    pub fn forget_ignore_state(&self) {
        self.ignoring.store(false, Ordering::Relaxed);
    }

    pub fn set_active(&self, on: bool) {
        let mut guard = self.active.lock().unwrap();
        *guard = on;
        self.cv.notify_all();
    }

    fn wait_until_active(&self) {
        let mut guard = self.active.lock().unwrap();
        while !*guard {
            guard = self.cv.wait(guard).unwrap();
        }
    }

    fn is_active(&self) -> bool {
        *self.active.lock().unwrap()
    }
}

pub fn window(app: &AppHandle) -> Option<WebviewWindow> {
    app.get_webview_window(WINDOW_LABEL)
}

fn monitor_contains(m: &Monitor, x: f64, y: f64) -> bool {
    let p = m.position();
    let s = m.size();
    x >= p.x as f64
        && x < (p.x + s.width as i32) as f64
        && y >= p.y as f64
        && y < (p.y + s.height as i32) as f64
}

/// The display the island lives on: the primary one, or the one under the cursor.
pub fn target_monitor(app: &AppHandle, pref: &str) -> Option<Monitor> {
    let monitors = app.available_monitors().ok()?;
    if pref == "cursor" {
        if let Some((cx, cy)) = cursor_physical() {
            if let Some(m) = monitors.iter().find(|m| monitor_contains(m, cx, cy)) {
                return Some(m.clone());
            }
        }
    }
    app.primary_monitor()
        .ok()
        .flatten()
        .or_else(|| monitors.into_iter().next())
}

/// The zoom to give the webview so that one CSS pixel is one window logical pixel again. WebView2's devicePixelRatio can differ from the window's scale factor
/// (system text scaling, a mixed-DPI setup): a 720 px window then holds fewer CSS pixels than the 640 px island needs and clips it. `None` when they agree to
/// within 2 % or when either number is unusable.
pub fn calculate_zoom_correction(current_zoom: f64, scale: f64, dpr: f64) -> Option<f64> {
    if dpr <= 0.0 || !dpr.is_finite() || scale <= 0.0 || !scale.is_finite() {
        return None;
    }
    if (dpr - scale).abs() / scale < 0.02 {
        return None;
    }
    Some((current_zoom * (scale / dpr)).clamp(0.25, 4.0))
}

#[cfg(test)]
mod zoom_tests {
    use super::*;

    #[test]
    fn no_correction_when_the_ratio_matches_the_window_scale() {
        assert_eq!(calculate_zoom_correction(1.0, 1.0, 1.0), None);
        assert_eq!(calculate_zoom_correction(1.0, 1.25, 1.25), None);
        assert_eq!(calculate_zoom_correction(1.0, 1.0, 1.01), None, "within 2 %");
    }

    #[test]
    fn a_dpi_mismatch_is_corrected() {
        assert_eq!(calculate_zoom_correction(1.0, 1.0, 1.25), Some(0.8));
        assert_eq!(calculate_zoom_correction(1.0, 1.25, 1.5625), Some(0.8));
        assert_eq!(calculate_zoom_correction(1.0, 1.5, 1.0), Some(1.5));
    }

    #[test]
    fn the_correction_is_clamped_and_unusable_inputs_change_nothing() {
        assert_eq!(calculate_zoom_correction(1.0, 8.0, 1.0), Some(4.0));
        assert_eq!(calculate_zoom_correction(1.0, 1.0, 100.0), Some(0.25));
        assert_eq!(calculate_zoom_correction(1.0, 0.0, 1.0), None);
        assert_eq!(calculate_zoom_correction(1.0, 1.0, -1.0), None);
        assert_eq!(calculate_zoom_correction(1.0, f64::NAN, 1.0), None);
        assert_eq!(calculate_zoom_correction(1.0, 1.0, f64::INFINITY), None);
    }
}

pub fn screen_info(app: &AppHandle, pref: &str) -> ScreenInfo {
    match target_monitor(app, pref) {
        Some(m) => {
            let scale = m.scale_factor();
            let p = m.position();
            let s = m.size();
            ScreenInfo {
                x: p.x as f64 / scale,
                y: p.y as f64 / scale,
                width: s.width as f64 / scale,
                height: s.height as f64 / scale,
                scale,
            }
        }
        None => ScreenInfo { x: 0.0, y: 0.0, width: 1920.0, height: 1080.0, scale: 1.0 },
    }
}

/// Places and sizes the window. `collapsed` picks the wake strip instead of the panel.
pub fn apply_geometry(app: &AppHandle, pref: &str, collapsed: bool) {
    let Some(win) = window(app) else { return };
    let Some(m) = target_monitor(app, pref) else { return };

    let scale = m.scale_factor();
    let mp = *m.position();
    let ms = *m.size();

    let (lw, lh) = if collapsed { (STRIP_W, STRIP_H) } else { (PANEL_W, PANEL_H) };
    let pw = (lw * scale).round().max(1.0) as u32;
    let ph = (lh * scale).round().max(1.0) as u32;
    let x = mp.x + (ms.width as i32 - pw as i32) / 2;
    let y = mp.y;

    // GTK never sizes a non-resizable window below its natural size (200 px
    // here), so on Linux the 6 px wake strip would stay a 200 px block. tao
    // re-applies the config's `resizable: false` after the first configure, so
    // this is asked every time, just before the resize. Undecorated, the window
    // still offers the user nothing to resize it by. (Found by @YossiYad, #44.)
    #[cfg(target_os = "linux")]
    let _ = win.set_resizable(true);
    let _ = win.set_size(PhysicalSize::new(pw, ph));
    let _ = win.set_position(PhysicalPosition::new(x, y));
    // Moving across displays can rescale the window: re-assert the physical size.
    let _ = win.set_size(PhysicalSize::new(pw, ph));
    let _ = win.set_always_on_top(true);

    // Moving across displays or waking from the strip can clamp or lag the resize. If the physical inner size is not what was asked, ask once more.
    if let Ok(got) = win.inner_size() {
        if got.width != pw || got.height != ph {
            crate::log::line(format!(
                "window size mismatch: wanted {pw}x{ph}, got {}x{} (scale {scale}, monitor {}x{})",
                got.width, got.height, ms.width, ms.height
            ));
            let _ = win.set_size(PhysicalSize::new(pw, ph));
            let _ = win.set_position(PhysicalPosition::new(x, y));
        }
    }
}

/// Position, size and scale of the monitor the island lives on. Any change here
/// means the island has to be placed again.
fn current_screen_key(app: &AppHandle) -> Option<(i32, i32, u32, u32, u64)> {
    let pref = app
        .try_state::<crate::Shared>()
        .map(|s| s.settings.lock().unwrap().screen.clone())
        .unwrap_or_else(|| "primary".into());
    let m = target_monitor(app, &pref)?;
    let p = m.position();
    let size = m.size();
    Some((p.x, p.y, size.width, size.height, m.scale_factor().to_bits()))
}

/// Emits `cursor` (window-logical coordinates) at ~60 Hz while the island is
/// visible. Parked on a condvar the rest of the time.
pub fn spawn_cursor_poll(app: AppHandle, gate: Arc<PollGate>) {
    std::thread::spawn(move || {
        let mut was_down = false;
        // The outside click: edges of the mouse buttons, read only while the page watches.
        let mut buttons = ButtonEdges::default();
        let mut was_watching = false;
        // Remembered across wakes so a display change while hidden is noticed the
        // moment the island comes back.
        let mut last_screen: Option<(i32, i32, u32, u32, u64)> = None;
        // Without a cursor to read (Linux) the loop only watches the display
        // layout, and twice a second is plenty for that: waking at 60 Hz just to
        // find no cursor costs CPU for nothing.
        let (period, screen_every) = if platform::pointer_feed() { (16, 30) } else { (500, 1) };
        loop {
            gate.wait_until_active();
            let mut last = (f64::MIN, f64::MIN);
            let mut ticks: u32 = 0;
            while gate.is_active() {
                std::thread::sleep(Duration::from_millis(period));

                // Monitors get plugged in, unplugged, rearranged and rescaled, and
                // an island pinned to coordinates that no longer exist is an island
                // nobody can reach. Checked about twice a second — the cursor poll
                // is already running, so this costs one monitor query.
                ticks = ticks.wrapping_add(1);
                if ticks % screen_every == 0 {
                    let now = current_screen_key(&app);
                    if now.is_some() && now != last_screen {
                        let first = last_screen.is_none();
                        last_screen = now;
                        if !first {
                            crate::log::line("display layout changed — repositioning".to_string());
                            let _ = app.emit_to(WINDOW_LABEL, "screen-changed", ());
                        }
                    }
                }

                let Some(win) = window(&app) else { continue };
                let Ok(origin) = win.outer_position() else { continue };
                let scale = win.scale_factor().unwrap_or(1.0);
                let Some((cx, cy)) = cursor_physical() else { continue };
                let x = (cx - origin.x as f64) / scale;
                let y = (cy - origin.y as f64) / scale;
                let size = match win.inner_size() {
                    Ok(s) => (s.width as f64 / scale, s.height as f64 / scale),
                    Err(_) => (PANEL_W, PANEL_H),
                };
                // The outside click: while the page watches (the island is expanded) the buttons are read on EVERY tick, moved or not, because a click does not move the pointer.
                // A button already held when the watch starts is adopted without an edge, so its release is not taken for a click.
                let watching = gate.watch_buttons.load(Ordering::Relaxed);
                if watching != was_watching {
                    was_watching = watching;
                    buttons.sync(watching && platform::any_button_down());
                } else if watching {
                    if let Some(edge) = buttons.step(platform::any_button_down()) {
                        let press = edge == Edge::Press;
                        let own = press && platform::press_is_own(&app, cx, cy);
                        let _ = win.emit("pointer-button", ButtonPayload { down: press, x, y, own });
                    }
                }
                let moved = !((x - last.0).abs() < 1.0 && (y - last.1).abs() < 1.0);
                // A new island shape (the wings folding) is applied even when the pointer has not moved.
                if !moved && !gate.take_rect_dirty() {
                    continue;
                }
                last = (x, y);

                // Click-through: the window only takes the mouse over the island
                // shape. A small entry margin means the flag is already off by the
                // time a moving cursor reaches a button.

                // A file being dragged has to be able to find us. WS_EX_TRANSPARENT
                // — what click-through is on Windows — hides the window from
                // WindowFromPoint, so OLE finds no drop target and shows the "no
                // drop" cursor. macOS has no such problem: AppKit delivers drags to
                // registered destinations whatever ignoresMouseEvents says. So while
                // a button is held anywhere over the panel, the whole panel takes
                // the mouse, which also makes the drop zone as forgiving as the Mac's.
                // A press may be the start of a drag: make sure the drop target is
                // ours before the file arrives.
                let down = left_button_down();
                if down && !was_down {
                    let handle = app.clone();
                    let _ = app.run_on_main_thread(move || platform::unblock_webview_drops(&handle));
                }
                was_down = down;

                let r = *gate.rect.lock().unwrap();
                let accept = takes_mouse(x, y, r, down, size);
                // Click-through by WS_EX_TRANSPARENT is the Windows poll's job. Where the pointer is read without it (Linux under X11, platform::pointer_feed) the input region stays the click-through.
                if platform::CURSOR_POLL {
                    if gate.ignoring.load(Ordering::Relaxed) == accept {
                        gate.ignoring.store(!accept, Ordering::Relaxed);
                        let _ = win.set_ignore_cursor_events(!accept);
                    }
                }

                let _ = win.emit("cursor", CursorPayload { x, y, down: platform::any_button_down() });
            }
        }
    });
}

/// Whether the window takes the mouse at a point (window-logical px): over the island's rect (with the entry margin), or, while a button is held, over the top `DRAG_H` of the window.
/// The window's own size bounds the drag zone and is never the hit area otherwise.
fn takes_mouse(x: f64, y: f64, r: IslandRect, down: bool, size: (f64, f64)) -> bool {
    let on_island = r.w > 0.0 && x >= r.x - HIT_MARGIN && x <= r.x + r.w + HIT_MARGIN && y >= r.y - HIT_MARGIN && y <= r.y + r.h + HIT_MARGIN;
    let dragging = down && x >= 0.0 && x <= size.0 && y >= 0.0 && y <= size.1.min(DRAG_H);
    on_island || dragging
}

/// The input region (x, y, w, h) where the pointer is not read (Linux): the wake strip while collapsed, otherwise the island's rect with the margin; empty before anything is drawn.
fn click_region(collapsed: bool, r: IslandRect) -> (f64, f64, f64, f64) {
    if collapsed {
        // The wake strip itself, never "the whole window": if the window ever fails to shrink to the strip, the rest of it must not swallow clicks meant for whatever sits under the top of the screen.
        (0.0, 0.0, STRIP_W, STRIP_H)
    } else if r.w <= 0.0 {
        // Nothing drawn yet: nothing takes the mouse.
        (0.0, 0.0, 0.0, 0.0)
    } else {
        let x0 = (r.x - HIT_MARGIN).max(0.0);
        let y0 = (r.y - HIT_MARGIN).max(0.0);
        (x0, y0, r.x + r.w + HIT_MARGIN - x0, r.y + r.h + HIT_MARGIN - y0)
    }
}

/// Re-applies click-through after the window or the island changed shape.
///
/// With the cursor poll (Windows) the window takes the mouse again and the next
/// tick decides from the cursor. Without it (Linux) the input region is set to
/// the island itself, or to the whole wake strip while collapsed.
pub fn refresh_click_through(app: &AppHandle, gate: &PollGate) {
    if platform::CURSOR_POLL {
        set_ignore_cursor(app, false);
        gate.forget_ignore_state();
        return;
    }
    let Some(win) = window(app) else { return };
    let region = Some(click_region(gate.collapsed.load(Ordering::Relaxed), *gate.rect.lock().unwrap()));
    platform::set_input_region(&win, region);
}

pub fn set_ignore_cursor(app: &AppHandle, ignore: bool) {
    if let Some(win) = window(app) {
        let _ = win.set_ignore_cursor_events(ignore);
    }
}

#[cfg(test)]
mod hit_tests {
    use super::*;

    const CHAT: IslandRect = IslandRect { x: 40.0, y: 0.0, w: 640.0, h: 560.0 };
    const OVERVIEW: IslandRect = IslandRect { x: 40.0, y: 0.0, w: 640.0, h: 160.0 };

    #[test]
    fn the_panel_is_taller_than_the_biggest_chat_and_the_island_is_not_the_panel() {
        assert!(PANEL_H >= 560.0 + 22.0);
        assert_eq!(PANEL_H, 600.0);
    }

    #[test]
    fn the_mouse_is_taken_over_the_island_and_its_margin_only() {
        // A short island in a 600 tall window: the rest of the panel is click-through.
        assert!(takes_mouse(360.0, 100.0, OVERVIEW, false, (PANEL_W, PANEL_H)));
        assert!(takes_mouse(360.0, 160.0 + HIT_MARGIN, OVERVIEW, false, (PANEL_W, PANEL_H)));
        assert!(!takes_mouse(360.0, 160.0 + HIT_MARGIN + 1.0, OVERVIEW, false, (PANEL_W, PANEL_H)));
        assert!(!takes_mouse(360.0, 590.0, OVERVIEW, false, (PANEL_W, PANEL_H)), "the bottom of the window is not the island");
        assert!(!takes_mouse(10.0, 100.0, OVERVIEW, false, (PANEL_W, PANEL_H)), "left of the island");
        // The big chat: its own rect, not the window's.
        assert!(takes_mouse(360.0, 560.0, CHAT, false, (PANEL_W, PANEL_H)));
        assert!(!takes_mouse(360.0, 560.0 + HIT_MARGIN + 1.0, CHAT, false, (PANEL_W, PANEL_H)));
        // Nothing drawn: nothing takes the mouse.
        assert!(!takes_mouse(360.0, 10.0, IslandRect::default(), false, (PANEL_W, PANEL_H)));
    }

    #[test]
    fn a_held_button_widens_the_drop_zone_to_the_old_window_and_no_further() {
        // A file being dragged finds the window over the area the 720 x 320 panel had; the taller window does not swallow drops meant for what lies below.
        assert!(takes_mouse(10.0, 300.0, OVERVIEW, true, (PANEL_W, PANEL_H)));
        assert!(!takes_mouse(10.0, 321.0, OVERVIEW, true, (PANEL_W, PANEL_H)));
        assert!(!takes_mouse(10.0, 590.0, OVERVIEW, true, (PANEL_W, PANEL_H)));
        assert!(!takes_mouse(10.0, 300.0, OVERVIEW, false, (PANEL_W, PANEL_H)), "no button, no drop zone");
        assert!(!takes_mouse(730.0, 100.0, OVERVIEW, true, (PANEL_W, PANEL_H)), "past the window's width");
        // A smaller window (the wake strip) still bounds it.
        assert!(!takes_mouse(10.0, 100.0, OVERVIEW, true, (STRIP_W, STRIP_H)));
    }

    #[test]
    fn the_linux_input_region_is_the_island_and_its_margin_and_never_the_window() {
        let g = |c, r| click_region(c, r);
        assert_eq!(g(true, CHAT), (0.0, 0.0, STRIP_W, STRIP_H), "collapsed: the wake strip");
        assert_eq!(g(false, IslandRect::default()), (0.0, 0.0, 0.0, 0.0), "nothing drawn: nothing takes the mouse");
        let (x, y, w, h) = g(false, OVERVIEW);
        assert_eq!((x, y, w, h), (40.0 - HIT_MARGIN, 0.0, 640.0 + 2.0 * HIT_MARGIN, 160.0 + HIT_MARGIN));
        let (_, y, _, h) = g(false, CHAT);
        assert_eq!(y + h, 560.0 + HIT_MARGIN);
        assert!(y + h < PANEL_H, "the foot of the window stays click-through");
    }
}
