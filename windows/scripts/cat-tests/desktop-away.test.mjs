import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// Away and awake (sub-project H): the seams between the desktop page and Rust, pinned by source.
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const rust = (rel) => fs.readFileSync(new URL(`../../src-tauri/${rel}`, import.meta.url), "utf8");

test("the page treats a locked session and a display that is off as hidden, tells Rust when it is awake, holds its cursor reads to 10 Hz and takes the system's double-click time; Rust watches the platform's own notifications and checks only while awake", () => {
  const body = source("desktop/body.ts"), d = rust("src/desktop.rs"), l = rust("src/lib.rs");
  assert.match(body, /hidden: document\.visibilityState === "hidden" \|\| this\.away,/);
  assert.match(body, /case "away": this\.away = m\.on; break;/);
  assert.match(body, /void Bridge\.desktopAwake\(awake\);/);
  assert.match(body, /if \(t - this\.lastCursor < 100\) return;/);
  assert.match(body, /this\.gest\.doubleMs = ms;/);
  assert.match(source("cat/desktoptrip.ts"), /\{ k: "away"; on: boolean \}/);
  assert.match(source("cat/gestures.ts"), /export const DOUBLE_MS = 500;/);
  assert.match(d, /CHECK_MS && \(gate\.awake\.load\(Ordering::Relaxed\) \|\| covered\)/);
  assert.match(d, /pub fn desktop_awake\(/);
  assert.match(d, /pub fn desktop_double_click_ms\(\) -> Option<u32>/);
  assert.match(l, /platform::watch_away\(move \|source, on\|/);
  assert.match(rust("src/platform/windows.rs"), /WTSRegisterSessionNotification/);
  assert.match(rust("src/platform/windows.rs"), /GetDoubleClickTime/);
  assert.match(rust("src/platform/linux.rs"), /org\.freedesktop\.login1/);
  assert.match(rust("src/platform/linux.rs"), /gtk_double_click_time/);
});

test("a lock and a display that is off are two causes, the poll parks while away, and Linux watches its own session's LockedHint", () => {
  const body = source("desktop/body.ts"), d = rust("src/desktop.rs"), w = rust("src/platform/windows.rs"), x = rust("src/platform/linux.rs");
  // One flag per cause, combined in one place that both watchers use.
  assert.match(d, /pub struct AwayState \{/);
  assert.match(d, /pub fn set_locked\(&mut self, on: bool\) -> Option<bool>/);
  assert.match(d, /pub fn set_off\(&mut self, on: bool\) -> Option<bool>/);
  assert.match(d, /pub fn display_away\(state: u8\) -> Option<bool>/);
  assert.match(w, /display_away\(s\.Data\[0\]\)/);
  assert.match(w, /tell\(AwaySource::Locked, true\)/);
  assert.doesNotMatch(w, /tell\(s\.Data\[0\] == 0\)/);
  // The poll thread parks on its condvar while the cat is home or away: no atomic-read wake-ups.
  assert.match(d, /pub fn parked\(active: bool, away: bool\) -> bool \{\s*!active \|\| away/);
  assert.match(d, /gate\.wait_until_running\(\);/);
  assert.match(d, /while gate\.is_running\(\) \{/);
  // Linux: this process's own session, its Lock and Unlock, its LockedHint, and the initial value.
  assert.match(x, /GetSessionByPID/);
  assert.match(x, /org\.freedesktop\.DBus\.Properties/);
  assert.match(x, /"PropertiesChanged"/);
  assert.match(x, /lookup::<bool>\("LockedHint"\)/);
  assert.match(x, /"LockedHint"\)\.to_variant\(\)/);
  // Bus data is read only through shape-checked readers: glib's child_value and VariantDict::new assert, and a panic in a gio callback aborts the app.
  assert.match(x, /fn prepare_for_sleep\(params: &gtk::glib::Variant\) -> Option<bool>/);
  assert.match(x, /if let Some\(off\) = prepare_for_sleep\(params\)/);
  assert.match(x, /try_child_value\(1\)\?\.get::<gtk::glib::VariantDict>\(\)\?/);
  assert.doesNotMatch(x, /\.child_value\(/);
  assert.doesNotMatch(x, /VariantDict::new\(Some/);
  assert.match(x, /AwaySource::Locked/);
  assert.match(x, /AwaySource::Off/);
  // The page asks for no cursor while away, and the message loop ends on an error.
  assert.match(body, /this\.cursorAsked \|\| this\.flight \|\| this\.carrying \|\| this\.dragging \|\| this\.away \|\|/);
  assert.match(w, /while GetMessageW\(&mut msg, None, 0, 0\)\.0 > 0 \{/);
});
