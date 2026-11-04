import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { WardrobeClock } from "../../src/island/wardrobe.ts";
import { cleanCatBlock, withOutfit } from "../../src/cat/display.ts";

// The desktop cat's right-click menu gains a Wardrobe submenu (sub-project I). It needs the native menu of a Tauri window, so it is pinned by source here and looked at in the owner's real-build checks.
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const root = (rel) => fs.readFileSync(new URL(`../../${rel}`, import.meta.url), "utf8");

test("the menu keeps Open the notch, Send home and Size as they were, and adds Wardrobe last", () => {
  const b = source("desktop/body.ts");
  assert.match(b, /const open = await MenuItem\.new\(\{ id: "open", text: "Open the notch"/);
  assert.match(b, /const home = await MenuItem\.new\(\{ id: "home", text: "Send home"/);
  assert.match(b, /items: \[open, home, await Submenu\.new\(\{ text: "Size", items: sizes \}\), await Submenu\.new\(\{ text: "Wardrobe", items: wardrobe\.items \}\)\]/);
  assert.match(b, /const sizes = await Promise\.all\(DESKTOP_SIZE_IDS\.map\(/, "the size items are built as before");
  assert.match(b, /private menuParts: Promise<\{ menu: Menu; sizes: CheckMenuItem\[\]; wardrobe: WardrobeItems \}> \| null = null;/, "the menu is still built once and reused");
  assert.match(b, /tickWardrobe\(parts\.wardrobe, this\.look\?\.outfitChoice\)/);
  assert.match(b, /buildWardrobeItems\(\(id\) => this\.say\(\{ k: "outfit", id \}\)\)/);
});

test("the shared items: the 18 choices in the contract's order, the groups apart with a disabled heading each, and a tick that follows the stored choice", () => {
  const m = source("core/wardrobemenu.ts");
  assert.match(m, /import \{ OUTFIT_GROUPS, OUTFIT_IDS, OUTFIT_NAMES, outfitIdOf \} from "\.\.\/cat\/wardrobe";/);
  assert.match(m, /OUTFIT_IDS\.map\(\(id\) => CheckMenuItem\.new\(\{ id: `outfit-\$\{id\}`, text: OUTFIT_NAMES\[id\], checked: false, action: \(\) => pick\(id\) \}\)\)/);
  assert.match(m, /for \(const \[gi, g\] of OUTFIT_GROUPS\.entries\(\)\) \{\s*if \(gi\) items\.push\(await PredefinedMenuItem\.new\(\{ item: "Separator" \}\)\);\s*if \(g\.name\) items\.push\(await MenuItem\.new\(\{ id: `outfit-group-\$\{g\.id\}`, text: g\.name, enabled: false \}\)\);\s*for \(const id of g\.ids\) items\.push\(ticks\[OUTFIT_IDS\.indexOf\(id\)\]\);/);
  assert.match(m, /const id = outfitIdOf\(choice\);\s*await Promise\.all\(w\.ticks\.map\(\(c, i\) => c\.setChecked\(OUTFIT_IDS\[i\] === id\)\)\);/);
});

test("a pick goes to the island's page, which stores it through withOutfit, saves, resolves it again and tells the body how the cat looks", () => {
  const t = source("cat/desktoptrip.ts"), d = source("island/desktop.ts"), i = source("island/island.ts");
  assert.match(t, /\| \{ k: "outfit"; id: string \}/);
  assert.match(t, /outfitChoice: string;/);
  assert.match(d, /outfitChoice: State\.settings\.cat\.outfit,/);
  assert.match(d, /case "outfit":\s*\/\/[^\n]*\n\s*State\.settings\.cat = withOutfit\(State\.settings\.cat, m\.id\);\s*void Bridge\.saveSettings\(State\.settings\);\s*this\.host\.outfitChanged\(\);\s*this\.sendLook\(true\);\s*break;/);
  assert.match(d, /outfitChanged\(\): void;/);
  assert.match(i, /outfitChanged: \(\) => this\.wardrobe\.sync\(\),/);
});

test("a desktop-menu pick reaches the clock the way a Settings click does, and an explicit outfit clears Auto's armed timer", () => {
  // The pick is saved, the save comes back as settings-changed to the island's page, and applySettings tells the clock (the same chain as Settings).
  const d = source("island/desktop.ts"), m = source("main.ts"), i = source("island/island.ts");
  assert.match(d, /case "outfit":[\s\S]*?void Bridge\.saveSettings\(State\.settings\);/);
  assert.match(m, /await onEvent<Settings>\("settings-changed", \(s\) => \{\s*State\.settings = \{ \.\.\.State\.settings, \.\.\.s \};\s*island\.applySettings\(\);/);
  assert.match(i, /applySettings\(\) \{[\s\S]*?this\.wardrobe\.sync\(\);\s*State\.notify\(\);\s*\}/);
  // Auto arms its midnight timer; the desktop menu's explicit pick cancels it.
  const timers = new Map();
  let id = 1, choice = "auto";
  const clock = new WardrobeClock({ now: () => new Date(2025, 11, 25, 12), choice: () => choice, set: (fn, ms) => { timers.set(id, fn); return id++; }, clear: (k) => timers.delete(k), apply: () => {} });
  clock.sync();
  assert.equal(timers.size, 1, "Auto arms its midnight timer");
  choice = withOutfit(cleanCatBlock({ outfit: "auto" }), "bell").outfit;
  clock.sync();
  assert.equal(timers.size, 0, "the explicit outfit cancels the timer");
});

test("the desktop window may show a menu already, and its Rust side needed no change", () => {
  assert.match(root("src-tauri/capabilities/desktop.json"), /"core:menu:default"/);
});
