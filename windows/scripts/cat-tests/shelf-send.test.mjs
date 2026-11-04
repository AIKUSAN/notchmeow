import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// Send and Show in folder (G1). The Share window and the file managers are the system's; what a test can pin is who calls what, on which thread, with what, and that the shelf never logs
// a name or a recipient.
const read = (rel) => fs.readFileSync(new URL(`../../${rel}`, import.meta.url), "utf8");
const lib = read("src-tauri/src/lib.rs"), isl = read("src/island/island.ts");
const win = read("src-tauri/src/platform/windows.rs"), lin = read("src-tauri/src/platform/linux.rs"), share = read("src-tauri/src/platform/windows/share.rs");

test("Send is the Windows Share window and Linux has none: one switch per system, read by the boot info, by the command and by the view", () => {
  assert.match(win, /pub const SHARE: bool = (?:true|false);/, "the fallback, if the Share window will not open from the island, is this one word");
  assert.match(lin, /pub const SHARE: bool = false;/);
  assert.match(lin, /pub fn share_files\(_win: &WebviewWindow, _paths: &\[PathBuf\]\) -> Result<\(\), String> \{\s*Err\(/);
  assert.match(lib, /shelf: ShelfCaps \{ drag_out: dragout::supported\(\), send: platform::SHARE \},/);
  assert.match(lib, /async fn shelf_send\(app: AppHandle, ids: Vec<String>\) -> Result<\(\), String> \{\s*if !platform::SHARE \{/);
  assert.match(read("src/views/shelf.ts"), /e\.missing \|\| !State\.shelfCaps\.send \? null/, "no Send button where the system has no share");
});

test("the Windows Share window: files are resolved on a worker thread, the window is asked for on the main thread, over the island's window made activatable for the moment", () => {
  assert.match(win, /let items = share::prepare\(paths\)\?;/);
  assert.match(win, /win\.run_on_main_thread\(move \|\| \{\s*set_activating\(&target, true\);\s*let _ = target\.set_focus\(\);\s*let shown = share::show\(HWND\(raw as \*mut _\), items\);\s*set_activating\(&target, false\);/);
  assert.match(lib, /blocking\(move \|\| \{\s*let paths = shelf_store\(\)\.resolve\(&ids\);\s*if paths\.is_empty\(\) \{\s*return Err\("Those files are gone\.".to_string\(\)\);\s*\}\s*log::line\("shelf send started"\);\s*platform::share_files\(&win, &paths\)/);
  assert.match(share, /DataTransferManager, IDataTransferManagerInterop|factory::<DataTransferManager, IDataTransferManagerInterop>\(\)/);
  assert.match(share, /interop\.ShowShareUIForWindow\(window\)/);
  assert.match(share, /\.SetStorageItems\(&IIterable::<IStorageItem>::from\(/);
});

test("the log says only that a send started: no name, no path, no id, no recipient anywhere in the send or show code", () => {
  const send = lib.slice(lib.indexOf("async fn shelf_reveal"), lib.indexOf("/// Ask: the shelf item"));
  assert.deepEqual([...send.matchAll(/log::line\(([^)]*)\)/g)].map((m) => m[1]), ['"shelf send started"']);
  assert.doesNotMatch(share, /log::|println!|eprintln!/);
  assert.doesNotMatch(isl.slice(isl.indexOf("private sendShelf"), isl.indexOf("/** Whether the OS has a global cursor")), /Bridge\.log\([^)]*ids/);
});

test("Show in folder selects the file: Explorer's /select with its own quoting on Windows, the file manager's ShowItems on Linux, the folder as the fallback; one item, by id", () => {
  assert.match(win, /Command::new\("explorer"\)\.raw_arg\(format!\("\/select,\\"\{\}\\"", path\.display\(\)\)\)\.spawn\(\);/);
  assert.match(lin, /Command::new\("gdbus"\)\.args\(crate::dragout::show_items_args\(path\)\)\.status\(\)/);
  assert.match(lin, /if !asked \{\s*if let Some\(parent\) = path\.parent\(\) \{\s*reveal_folder\(&parent\.to_string_lossy\(\)\);/);
  assert.match(lib, /async fn shelf_reveal\(id: String\) -> Result<\(\), String>/);
  assert.match(read("src/views/shelf.ts"), /act\.reveal\(e\.id\)/);
});

test("the island holds itself open for the Share window and lets go afterwards; Send and Show do nothing the system cannot", () => {
  const out = isl.slice(isl.indexOf("private sendShelf(ids: string[]) {"), isl.indexOf("/** Whether the OS has a global cursor"));
  assert.match(out, /if \(!State\.shelfCaps\.send \|\| ids\.length === 0\) return;\s*this\.sendHold\.start\(\);\s*Bridge\.shelfSend\(ids\)/);
  assert.match(out, /\.finally\(\(\) => this\.sendHold\.finish\(\)\);/);
  assert.match(isl, /const SEND_HOLD_MS = 15_000;/);
  assert.match(isl, /shelf: \{ ask: \(id\) => this\.askShelf\(id\), send: \(ids\) => this\.sendShelf\(ids\), reveal: \(id\) => this\.revealShelf\(id\), dragOut: \(ids\) => this\.dragOutShelf\(ids\) \},/);
});

test("the Windows build names the crate and the features the Share window uses, and the lock file gains exactly that one edge", () => {
  const toml = read("src-tauri/Cargo.toml");
  assert.match(toml, /windows-collections = "0\.2"/);
  for (const f of ["ApplicationModel", "ApplicationModel_DataTransfer", "Foundation_Collections"]) assert.match(toml, new RegExp(`"${f}"`), f);
  assert.match(read("Cargo.lock"), / "windows 0\.61\.3",\n "windows-collections 0\.2\.0",\n "windows-core 0\.61\.2",\n "zip",\n\]/);
});
