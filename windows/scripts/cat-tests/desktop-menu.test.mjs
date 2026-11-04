import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// The tray's item and Settings' note under the switch (sub-project H), pinned by source.
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const rust = (rel) => fs.readFileSync(new URL(`../../src-tauri/${rel}`, import.meta.url), "utf8");
const root = (rel) => fs.readFileSync(new URL(`../../${rel}`, import.meta.url), "utf8");

test("the tray's item toggles the trip, its words follow the phase, and Settings names the system that places windows itself under the switch", () => {
  assert.match(source("main.ts"), /case "desktop":\s*void desktop\.toggle\(\);\s*break;/);
  assert.match(source("island/desktop.ts"), /phase: \(p\) => void Bridge\.desktopMenuText\(DESKTOP_PHASE_INFO\[p\]\.on\),/);
  assert.match(source("settings/cat.ts"), /\.\.\.\(host\.desktopNote \? \[h\("div", \{ class: "hint", text: host\.desktopNote \}\)\] : \[\]\),/);
  assert.match(source("settings/app.ts"), /desktopNote: boot && !boot\.desktopPositioned/);
  const t = rust("src/tray.rs"), l = rust("src/lib.rs"), d = rust("src/desktop.rs");
  assert.match(t, /MenuItem::with_id\(app, "desktop", "Cat on the desktop", true, None::<&str>\)/);
  assert.match(t, /if out \{ "Bring the cat home" \} else \{ "Cat on the desktop" \}/);
  assert.match(l, /desktop_positioned: platform::desktop_positioned\(\),/);
  assert.ok(l.includes("desktop::desktop_menu_text,") && d.includes("pub fn desktop_menu_text"));
});
