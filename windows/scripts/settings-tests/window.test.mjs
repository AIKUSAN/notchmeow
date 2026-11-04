// The Settings window's pins (Task 3): the Mac's sizes, the place the island asks for, the hidden event, and the callers that name a page.
// Rust and TypeScript are read as text here, never imported; the numbers are checked against src/settings/layout.ts.
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { MIN_W, MIN_H, DEFAULT_W, DEFAULT_H } from "../../src/settings/layout.ts";

const read = (rel) => fs.readFileSync(new URL(`../../${rel}`, import.meta.url), "utf8");
const lib = read("src-tauri/src/lib.rs");

test("the settings window is the Mac's size: 720 x 560 by default, 415 x 420 at least, and the layout.ts numbers match", () => {
  assert.ok(lib.includes(".inner_size(720.0, 560.0)"), "the default size");
  assert.ok(lib.includes(".min_inner_size(415.0, 420.0)"), "the minimum size");
  assert.ok(!lib.includes(".inner_size(560.0, 680.0)"), "the old default is gone");
  assert.ok(!lib.includes(".min_inner_size(460.0, 480.0)"), "the old minimum is gone");
  const size = lib.match(/\.inner_size\((\d+\.\d), (\d+\.\d)\)/);
  const min = lib.match(/\.min_inner_size\((\d+\.\d), (\d+\.\d)\)/);
  assert.deepEqual([Number(size[1]), Number(size[2])], [DEFAULT_W, DEFAULT_H]);
  assert.deepEqual([Number(min[1]), Number(min[2])], [MIN_W, MIN_H]);
});

test("settings_place keeps a page or page/tab, documented as the brief says", () => {
  assert.match(lib, /fn settings_place\(raw: Option<String>\) -> Option<String>/);
  assert.ok(lib.includes("The Settings place the island asks for (`devices`, `chat/keys`): lower-case letters and at most one slash; anything else is dropped, and the window opens where it was. The page reads it through `migrate`."));
});

test("open_settings_window takes the place, shows the window, then emits settings-place only for a kept place", () => {
  assert.match(
    lib,
    /fn open_settings_window\(app: AppHandle, place: Option<String>\) \{\s*show_settings_window\(&app\);\s*let asked = place\.is_some\(\);\s*match settings_place\(place\) \{\s*Some\(p\) => logged_emit\("settings-place", app\.emit_to\("settings", "settings-place", p\)\),\s*None if asked => log::line\("Settings place was not a page"\),\s*None => \{\}\s*\}\s*\}/,
  );
  const tray = read("src-tauri/src/tray.rs");
  assert.ok(tray.includes('"settings" => crate::show_settings_window(app),'), "the tray opens with no place");
});

test("the close handler emits settings-hidden right after the Devices reset, with the spec's comment", () => {
  assert.match(
    lib,
    /link_cmd::settings_hidden\(&app\);\n\s*\/\/ The page drops what was typed and not saved \(the restyle spec's rule 11\): the window is only hidden, so it never reloads\.\n\s*logged_emit\("settings-hidden", app\.emit_to\("settings", "settings-hidden", \(\)\)\);/,
  );
});

test("the bridge sends the optional place as null when there is none", () => {
  const bridge = read("src/core/bridge.ts");
  assert.ok(bridge.includes('openSettingsWindow: (place?: string) => call<void>("open_settings_window", { place: place ?? null }),'));
});

test("the callers name their page; Settings → Your AI is the first-run box; views.ts's own Settings button stays without a place", () => {
  const views = read("src/views/views.ts");
  assert.ok(views.includes("openSettingsWindow(place?: string): void;"), "the Actions type takes the optional place");
  assert.ok(views.includes('openSettings: () => actions.openSettingsWindow("services"),'), "the integration hooks open Services");
  assert.equal(views.split("actions.openSettingsWindow()").length - 1, 1, "views.ts keeps exactly one place-less call");

  const island = read("src/island/island.ts");
  assert.ok(island.includes("openSettingsWindow: (place?: string) => void Bridge.openSettingsWindow(place),"));

  const chat = read("src/views/chat.ts");
  assert.ok(chat.includes('actions.openSettingsWindow("chat/keys");'), "the auth-error action opens Keys");
  assert.ok(chat.includes('text: "Add a cloud key", onclick: () => actions.openSettingsWindow("chat/keys")'));
  assert.ok(chat.includes("// The first run: Settings → AI and chat opens on Your AI."), "the first-run comment");
  assert.ok(chat.includes('text: "Connect Claude", onclick: () => actions.openSettingsWindow("chat/yourai")'));

  const shelf = read("src/views/shelfdevice.ts");
  assert.ok(shelf.includes('text: "Open Devices", onclick: () => void Bridge.openSettingsWindow("devices")'));
});
