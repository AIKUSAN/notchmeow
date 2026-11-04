import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// The desktop cat's window (sub-project H): the Rust side and the files that make the page, pinned by source (no test program can open a window).
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const rust = (rel) => fs.readFileSync(new URL(`../../src-tauri/${rel}`, import.meta.url), "utf8");
const root = (rel) => fs.readFileSync(new URL(`../../${rel}`, import.meta.url), "utf8");

test("Rust: the window is made hidden at launch before the island's, takes no files and no focus, and its poll thread sleeps until the cat is out", () => {
  const d = rust("src/desktop.rs"), l = rust("src/lib.rs");
  assert.match(d, /\.visible\(false\)/);
  assert.match(d, /\.drag_and_drop\(false\)/);
  assert.match(d, /\.focused\(false\)/);
  assert.match(d, /gate\.wait_until_running\(\);/);
  assert.match(d, /flat_map\(\|c\| circle_rows\(c, HIT_SLACK\)\)/, "the input region is the circles' rows, not their squares");
  assert.match(d, /while gate\.is_running\(\) \{\s*std::thread::sleep/);
  assert.match(l, /create_settings_window\(&handle\);\s*create_chat_window\(&handle\);\s*desktop::create_window\(&handle\);\s*desktop::spawn_poll\(handle\.clone\(\)/);
  assert.ok(l.indexOf("desktop::create_window(&handle);") < l.indexOf("if let Some(win) = island::window(&handle)"), "before the island's webview, which WebView2 needs");
  for (const c of ["desktop_screens", "desktop_layout", "desktop_place", "desktop_show", "desktop_drag", "desktop_native_drag", "desktop_cursor", "desktop_relay"]) assert.ok(l.includes(`desktop::${c},`), c);
  assert.match(l, /pub\(crate\) const BROWSER_ARGS/);
  // M4: the page gets only what it uses (the event listener and the native menu); the app's own desktop_* commands need no permission (no app ACL manifest in build.rs).
  const caps = (name) => JSON.parse(root(`src-tauri/capabilities/${name}.json`));
  assert.deepEqual(caps("desktop").windows, ["desktop"]);
  assert.deepEqual(caps("desktop").permissions, ["core:event:default", "core:menu:default"]);
  assert.deepEqual(caps("default").windows, ["island", "settings", "chat"], "the desktop window is not in the default capability: no core:default, no autostart");
  assert.equal(root("src-tauri/build.rs").trim(), "fn main() {\n    tauri_build::build()\n}", "no AppManifest: the app's own commands are not behind an ACL");
  assert.match(root("vite.config.ts"), /desktop: resolve\(__dirname, "desktop\.html"\)/);
  assert.match(root("desktop.html"), /src="\/src\/desktop\/main\.ts"/);
});

test("Rust: the relay forwards only to the two windows, the top layer steps aside for fullscreen, and nothing in the window code reads a file or opens a network connection", () => {
  const d = rust("src/desktop.rs"), lin = rust("src/platform/linux.rs");
  assert.match(d, /"island" => crate::island::WINDOW_LABEL,\s*"desktop" => WINDOW_LABEL,\s*_ => return,/);
  assert.match(lin, /gtk_layer_set_layer\(ptr, layer::LAYER_TOP\);/);
  assert.doesNotMatch(d, /std::fs|reqwest|TcpStream|Command::new/);
});

test("Page: a file dropped on the desktop cat can never navigate its page (spec §2: no file drops on the desktop cat)", () => {
  const m = source("desktop/main.ts");
  assert.match(m, /window\.addEventListener\("dragover", \(e\) => e\.preventDefault\(\)\);/);
  assert.match(m, /window\.addEventListener\("drop", \(e\) => e\.preventDefault\(\)\);/);
});
