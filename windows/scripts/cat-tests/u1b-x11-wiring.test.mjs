import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// Where the X11 pointer feed is wired (platform/linux.rs, lib.rs, platform/windows.rs), pinned as source text. A real X server is not part of these checks.
const read = (rel) => fs.readFileSync(new URL(`../../src-tauri/src/${rel}`, import.meta.url), "utf8");
const linux = read("platform/linux.rs"), lib = read("lib.rs"), win = read("platform/windows.rs");

test("Xlib is linked directly and only seven calls are declared: the pointer's three, and focus awareness's one-shot foreground read", () => {
  assert.match(linux, /#\[link\(name = "X11"\)\]/);
  const calls = [...linux.matchAll(/pub fn (X[A-Za-z]+)\(/g)].map((m) => m[1]).sort();
  assert.deepEqual(calls, ["XDefaultRootWindow", "XFree", "XGetClassHint", "XGetWindowProperty", "XInternAtom", "XOpenDisplay", "XQueryPointer"]);
  // The extra four are focus awareness's one-shot foreground read (platform/linux.rs `foreground_app`); the rule stays: no event selection, nothing to listen to.
  assert.doesNotMatch(linux, /XSelectInput/);
  assert.match(linux, /thread_local! \{\s*static DISPLAY: Cell<usize>/, "one connection per thread: an Xlib display is not shared");
});

test("only a GDK X11 display counts, and Linux click-through stays the input region", () => {
  assert.match(linux, /d\.type_\(\)\.name\(\) == "GdkX11Display"/);
  assert.match(linux, /pub const CURSOR_POLL: bool = false;/);
  assert.match(linux, /if !pointer_feed\(\) \{\s*return None;\s*\}\s*x11_pointer\(\)/);
});

test("an X11 backend inside a Wayland session (XWayland) is not a pointer feed", () => {
  assert.match(linux, /x11_feed\(gdk_x11, std::env::var_os\("WAYLAND_DISPLAY"\)\.is_some\(\)\)/);
  assert.match(linux, /fn x11_feed\(gdk_is_x11: bool, wayland_display_set: bool\) -> bool \{\s*gdk_is_x11 && !wayland_display_set/);
});

test("the display is looked at on the main thread before the poll starts, and Windows has nothing to detect", () => {
  const detect = lib.indexOf("platform::detect_pointer_feed();");
  assert.ok(detect > 0 && detect < lib.indexOf("island::spawn_cursor_poll("), "detect, then spawn");
  assert.match(win, /pub fn detect_pointer_feed\(\) \{\}/);
});

test("the app's own window is asked of GDK on the main thread, for at most 40 ms, at presses only", () => {
  assert.match(linux, /app\.run_on_main_thread\(move \|\| \{/);
  assert.match(linux, /rx\.recv_timeout\(std::time::Duration::from_millis\(40\)\)/);
  assert.match(linux, /p\.window_at_position\(\)\.0\.is_some\(\)/);
});
