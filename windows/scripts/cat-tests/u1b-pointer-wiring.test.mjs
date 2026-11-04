import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// Where the Rust side of the outside click is wired (island.rs, lib.rs, the platform files), pinned as source text. The Windows-only code is compiled by CI (windows-tests.yml), not here.
const read = (rel) => fs.readFileSync(new URL(`../../${rel}`, import.meta.url), "utf8");
const island = read("src-tauri/src/island.rs"), lib = read("src-tauri/src/lib.rs"), win = read("src-tauri/src/platform/windows.rs"), linux = read("src-tauri/src/platform/linux.rs");

test("the poll reads the buttons on every tick, before the skip for a pointer that has not moved, and only while the page watches", () => {
  const watching = island.indexOf("let watching = gate.watch_buttons.load(Ordering::Relaxed);");
  const step = island.indexOf("buttons.step(platform::any_button_down())");
  const skip = island.indexOf("if !moved && !gate.take_rect_dirty() {");
  assert.ok(watching > 0 && step > watching && skip > step, "the watch flag, then the read, then the skip");
  assert.match(island, /if watching != was_watching \{\s*was_watching = watching;\s*buttons\.sync\(watching && platform::any_button_down\(\)\);/, "switching the watch on adopts a held button without reporting a press");
});

test("a press is checked against the app's own windows, a release is not, and the event carries the window's logical px", () => {
  assert.match(island, /let own = press && platform::press_is_own\(&app, cx, cy\);/);
  assert.match(island, /win\.emit\("pointer-button", ButtonPayload \{ down: press, x, y, own \}\)/);
});

test("a new island shape is applied even when the pointer has not moved, and every set_rect marks it", () => {
  assert.match(island, /pub fn set_rect\(&self, rect: IslandRect\) \{[^}]*self\.rect_dirty\.store\(true, Ordering::Relaxed\);/);
  assert.match(island, /pub fn take_rect_dirty\(&self\) -> bool \{\s*self\.rect_dirty\.swap\(false, Ordering::Relaxed\)/);
});

test("click-through by WS_EX_TRANSPARENT stays with the cursor poll of Windows, and the cursor event says whether a button is down", () => {
  assert.match(island, /if platform::CURSOR_POLL \{\s*if gate\.ignoring\.load\(Ordering::Relaxed\) == accept \{[\s\S]{0,200}set_ignore_cursor_events\(!accept\)/);
  assert.match(island, /CursorPayload \{ x, y, down: platform::any_button_down\(\) \}/);
  assert.match(island, /let \(period, screen_every\) = if platform::pointer_feed\(\) \{ \(16, 30\) \} else \{ \(500, 1\) \};/);
});

test("the page switches the watch with one command, and boot tells it whether the OS gives a pointer", () => {
  assert.match(lib, /fn watch_pointer_buttons\(shared: State<Shared>, on: bool\) \{\s*shared\.gate\.watch_buttons\.store\(on, Ordering::Relaxed\);/);
  assert.match(lib, /set_island_rect,\s*watch_pointer_buttons,\s*focus_window,/);
  assert.match(lib, /cursor_poll: platform::pointer_feed\(\),/);
  assert.match(lib, /^mod pointer;$/m);
});

test("Windows reads the three mouse buttons and asks which window is under the point; Linux has the same three names", () => {
  assert.match(win, /VK_LBUTTON, VK_MBUTTON, VK_RBUTTON/);
  assert.match(win, /WindowFromPoint/);
  assert.match(win, /pub fn pointer_feed\(\) -> bool/);
  assert.match(win, /pub fn any_button_down\(\) -> bool/);
  assert.match(win, /pub fn press_is_own\(_app: &AppHandle, x: f64, y: f64\) -> bool/);
  for (const name of ["pointer_feed", "any_button_down", "press_is_own"]) assert.match(linux, new RegExp(`pub fn ${name}\\(`), `Linux has ${name}`);
});

test("Windows compares the process of the point's top-level window, not of the WebView2 child under it", () => {
  const body = win.slice(win.indexOf("pub fn press_is_own"));
  const fn = body.slice(0, body.indexOf("\n}\n"));
  assert.match(fn, /GetAncestor\(hwnd, GA_ROOT\)/, "the root window is asked for");
  assert.match(fn, /GetWindowThreadProcessId\(root/, "its process is the one compared");
  assert.match(win, /GetAncestor,|GetAncestor\b[^;]*WindowFromPoint/, "GetAncestor is imported from WindowsAndMessaging");
  assert.match(win, /\bGA_ROOT\b[^;]*WindowFromPoint|WindowFromPoint[^;]*\bGA_ROOT\b|GA_ROOT,/, "GA_ROOT is imported");
});

test("no global mouse hook anywhere: the poll's button reads are the only source", () => {
  const dir = new URL("../../src-tauri/src/", import.meta.url);
  for (const f of fs.readdirSync(dir, { recursive: true })) {
    if (!String(f).endsWith(".rs")) continue;
    const text = fs.readFileSync(new URL(String(f), dir), "utf8");
    assert.doesNotMatch(text, /SetWindowsHookEx|WH_MOUSE_LL|XGrabPointer|XInput2|XISelectEvents/, `${f} installs no global mouse hook`);
  }
});
