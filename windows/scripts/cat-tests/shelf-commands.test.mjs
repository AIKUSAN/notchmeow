import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// The names the page calls and the commands Rust registers are two strings that nothing else ties together, and a mistake in one fails silently (the bridge answers null). This pins them:
// every shelf command and the drag-out commands in bridge.ts have a `#[tauri::command]` in lib.rs and are in `generate_handler!`, and the commands take ids, never a path (only a drop
// brings paths in).
const read = (rel) => fs.readFileSync(new URL(`../../${rel}`, import.meta.url), "utf8");
const bridge = read("src/core/bridge.ts"), lib = read("src-tauri/src/lib.rs");
const called = [...bridge.matchAll(/(?:call|callOrThrow)<[^>]*(?:<[^>]*>)?[^>]*>\("((?:shelf|drag_out)_?[a-z_]*)"/g)].map((m) => m[1]);
const handler = lib.slice(lib.indexOf("generate_handler!["), lib.indexOf("])", lib.indexOf("generate_handler![")));

test("the page's shelf and drag-out calls are the commands Rust registers", () => {
  assert.ok(called.includes("drag_out_spike"), `found ${called.join(", ")}`);
  for (const name of called) {
    assert.match(lib, new RegExp(`#\\[tauri::command\\]\\s*(?:async )?fn ${name}\\(`), `${name} is a command`);
    assert.match(handler, new RegExp(`\\b${name},`), `${name} is registered`);
  }
});

test("every shelf command that touches a file takes an id or a list of ids; only shelf_add takes paths (a drop's)", () => {
  for (const name of called.filter((n) => n.startsWith("shelf_"))) {
    const sig = lib.match(new RegExp(`fn ${name}\\(([^)]*)\\)`))[1];
    if (name === "shelf_add") assert.match(sig, /paths: Vec<String>/);
    else assert.doesNotMatch(sig, /path/i, `${name}(${sig})`);
  }
  assert.match(lib, /fn drag_out_spike\(app: AppHandle\)/, "the spike takes nothing: it makes its own file");
});

test("the spike refuses in a release build, and makes its own file, never one of the user's", () => {
  const spike = lib.slice(lib.indexOf("async fn drag_out_spike"), lib.indexOf("fn secret_present"));
  assert.match(spike, /if !cfg!\(debug_assertions\) \{\s*return Err\(/);
  assert.match(spike, /settings::local_dir\(\)\.join\("spike"\)/);
  assert.match(spike, /dragout::start\(&app, vec!\[file\]\)\.await/);
});

test("the drag source exists for both systems with the same shape, behind one type and one pair of switches", () => {
  const mod = read("src-tauri/src/platform/mod.rs"), win = read("src-tauri/src/platform/windows.rs"), lin = read("src-tauri/src/platform/linux.rs"), drag = read("src-tauri/src/dragout.rs");
  assert.match(mod, /pub type DragDone = Box<dyn FnOnce\(Result<&'static str, String>\)>;/);
  assert.match(win, /pub fn drag_out\(_win: &WebviewWindow, paths: Vec<PathBuf>, done: DragDone\)/);
  assert.match(lin, /pub fn drag_out\(win: &WebviewWindow, paths: Vec<PathBuf>, done: DragDone\)/);
  assert.match(drag, /pub const WINDOWS: bool = (?:true|false);\s*\/\/\/ Linux can drag[^\n]*\npub const LINUX: bool = (?:true|false);/, "one switch per system: the fallback is flipping one");
  assert.match(read("src-tauri/src/platform/windows/drag.rs"), /DoDragDrop\(&data, &source, DROPEFFECT_COPY, &mut effect\)/, "copy only: an original is never moved");
  assert.match(read("src-tauri/src/platform/linux/drag.rs"), /drag_begin_with_coordinates\(&targets, gdk::DragAction::COPY, 1, None, -1, -1\)/, "copy only");
  assert.match(drag, /win\.run_on_main_thread\(move \|\| \{/, "OLE and GTK both need the main thread");
});

test("the Windows build asks the windows crate for the features the drag source uses, and no crate of its own (G2's snow and mdns-sd are the link's)", () => {
  const toml = read("src-tauri/Cargo.toml");
  for (const f of ["Win32_System_Com", "Win32_System_SystemServices", "Win32_UI_Shell", "Win32_UI_Shell_Common", "Win32_System_Ole"]) assert.match(toml, new RegExp(`"${f}"`), f);
  const deps = toml.slice(toml.indexOf("\n[dependencies]"), toml.indexOf("\n[dev-dependencies]"));
  assert.deepEqual([...deps.matchAll(/^([a-z0-9_-]+) = /gm)].map((m) => m[1]), ["tauri", "tauri-plugin-single-instance", "tauri-plugin-autostart", "serde", "serde_json", "tokio", "reqwest", "lopdf", "zip", "snow", "mdns-sd", "sha2", "unicode-normalization", "getrandom"], "the only crates added since G1 are the link's");
  assert.match(toml, /^snow = "0\.9"$/m);
  assert.match(toml, /^mdns-sd = "0\.11"$/m);
});

test("the spike's tab is mounted only by the dev server, and presses with the same 4 px rule as everything else", () => {
  assert.match(read("src/main.ts"), /if \(import\.meta\.env\.DEV\) void import\("\.\/shelf\/dragspike"\)\.then\(\(m\) => m\.mountDragSpike\(\)\);/);
  const tab = read("src/shelf/dragspike.ts");
  assert.match(tab, /new PressDrag\(\)/);
  assert.match(tab, /Bridge\.dragOutSpike\(\)/);
});
