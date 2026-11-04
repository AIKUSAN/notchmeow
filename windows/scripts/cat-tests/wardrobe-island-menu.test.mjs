import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { wardrobeMenuHit } from "../../src/cat/menuhit.ts";
import { WardrobeClock } from "../../src/island/wardrobe.ts";
import { cleanCatBlock, withOutfit } from "../../src/cat/display.ts";

// The island cat's right-click menu (sub-project I): where it opens is pure and replayed here; what the window does with the event is pinned by source (it needs a Tauri window).
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const scene = (o = {}) => ({ mode: "compact", greeting: false, upload: false, desktopOut: false, bot: { cx: 100, cy: 20, r: 12 }, bot2: null, ...o });

test("a right-click opens the menu on the big cat in the compact and the open island, and nowhere else", () => {
  assert.equal(wardrobeMenuHit(100, 20, scene()), true);
  assert.equal(wardrobeMenuHit(111, 20, scene()), true, "inside the circle");
  assert.equal(wardrobeMenuHit(113, 20, scene()), false, "just outside");
  assert.equal(wardrobeMenuHit(100, 20, scene({ mode: "expanded" })), true);
  assert.equal(wardrobeMenuHit(300, 20, scene()), false, "off the cat");
  assert.equal(wardrobeMenuHit(Number.NaN, 20, scene()), false, "a point that is not a number hits nothing");
});

test("not while the island is hidden, the greeting or the drop sequence owns it, and not at the empty spot of a cat that is out on the desktop", () => {
  assert.equal(wardrobeMenuHit(100, 20, scene({ mode: "hidden" })), false);
  assert.equal(wardrobeMenuHit(100, 20, scene({ greeting: true })), false);
  assert.equal(wardrobeMenuHit(100, 20, scene({ upload: true })), false);
  assert.equal(wardrobeMenuHit(100, 20, scene({ desktopOut: true })), false);
});

test("Two cats: both cats open it, where the circles overlap the nearer cat's is the click, and a cat that is out leaves cat 2's menu", () => {
  const two = { bot: { cx: 80, cy: 20, r: 12 }, bot2: { cx: 100, cy: 20, r: 12 } };
  assert.equal(wardrobeMenuHit(70, 20, scene(two)), true, "cat 1");
  assert.equal(wardrobeMenuHit(110, 20, scene(two)), true, "cat 2");
  assert.equal(wardrobeMenuHit(90, 20, scene(two)), true, "the overlap");
  assert.equal(wardrobeMenuHit(70, 20, scene({ ...two, desktopOut: true })), false, "cat 1 is on the desktop: its spot is empty");
  assert.equal(wardrobeMenuHit(110, 20, scene({ ...two, desktopOut: true })), true, "cat 2 is still in the notch");
});

test("the island opens the menu on a right-click on a big cat, a right press there is not also a click, and every other press and the drag out are as they were", () => {
  const i = source("island/island.ts");
  assert.match(i, /this\.islandEl\.addEventListener\("contextmenu", \(e\) => \{\s*if \(!this\.onBigCat\(e\.clientX, e\.clientY\)\) return;\s*e\.preventDefault\(\);\s*void this\.showWardrobeMenu\(\);\s*\}\);/);
  assert.match(i, /if \(e\.button === 2 && this\.onBigCat\(x, y\)\) return;\s*if \(e\.button === 0 && this\.desktop\?\.canCarry && !State\.desktopNotchEmpty && State\.mode !== "hidden" && !this\.greetingShown\(\) && !this\.uploadActive && this\.isBotHit\(x, y\)\) \{\s*this\.press\.press\(x, y\);\s*this\.pressAction = \(\) => this\.pressed\(x, y\);\s*return;\s*\}\s*this\.pressed\(x, y\);/, "the left press, the click and the drag out are the lines they were");
  assert.match(i, /wardrobeMenuHit\(x, y, \{ mode: State\.mode, greeting: this\.greetingShown\(\), upload: this\.uploadActive, desktopOut: State\.desktopNotchEmpty, bot: this\.botCircle\(\), bot2: this\.cast\.second\?\.pill \? this\.bot2Circle\(\) : null \}\)/);
  assert.match(i, /items: \[await Submenu\.new\(\{ text: "Wardrobe", items: wardrobe\.items \}\)\]/, "only Wardrobe is in it for now");
  assert.match(i, /await tickWardrobe\(parts\.wardrobe, State\.settings\.cat\.outfit\);\s*await parts\.menu\.popup\(\);/);
  assert.match(i, /private pickOutfit\(id: OutfitId\): void \{\s*State\.settings\.cat = withOutfit\(State\.settings\.cat, id\);\s*void Bridge\.saveSettings\(State\.settings\);\s*this\.wardrobe\.sync\(\);\s*\}/);
  assert.equal((i.match(/Menu\.new\(/g) || []).length, 1, "one menu, built once");
});

test("the island's window may show a menu: core:default holds the menu permission", () => {
  const cap = fs.readFileSync(new URL("../../src-tauri/capabilities/default.json", import.meta.url), "utf8");
  assert.match(cap, /"windows": \["island", "settings", "chat"\]/);
  assert.match(cap, /"core:default"/);
});

test("a pick from the island's menu reaches the clock the way a Settings click does, and an explicit outfit clears Auto's armed timer", () => {
  // The chain, pinned by source: the pick is saved, the save comes back as settings-changed to the island's page, and applySettings tells the clock.
  const m = source("main.ts"), i = source("island/island.ts");
  assert.match(m, /await onEvent<Settings>\("settings-changed", \(s\) => \{\s*State\.settings = \{ \.\.\.State\.settings, \.\.\.s \};\s*island\.applySettings\(\);/);
  assert.match(i, /applySettings\(\) \{[\s\S]*?this\.wardrobe\.sync\(\);\s*State\.notify\(\);\s*\}/);
  // The path itself, run: the body of the island's real pickOutfit, with the island's State, Bridge and clock standing in. Auto arms its midnight timer; the menu's explicit pick cancels it.
  const body = /private pickOutfit\(id: OutfitId\): void \{([\s\S]*?)\n  \}/.exec(i)?.[1];
  assert.ok(body, "the island has a pickOutfit");
  const timers = new Map();
  let nextId = 1;
  const State = { settings: { cat: cleanCatBlock({ outfit: "auto" }) } };
  const saved = [];
  const Bridge = { saveSettings: (settings) => { saved.push(settings.cat.outfit); return Promise.resolve(); } };
  const wardrobe = new WardrobeClock({ now: () => new Date(2025, 11, 25, 12), choice: () => State.settings.cat.outfit, set: (fn) => { timers.set(nextId, fn); return nextId++; }, clear: (k) => timers.delete(k), apply: () => {} });
  wardrobe.sync();
  assert.equal(timers.size, 1, "Auto arms its midnight timer");
  new Function("State", "Bridge", "withOutfit", "id", body).call({ wardrobe }, State, Bridge, withOutfit, "bell");
  assert.deepEqual(saved, ["bell"], "the pick is saved");
  assert.equal(State.settings.cat.outfit, "bell", "and stored in the cat block");
  assert.equal(wardrobe.outfit, "bell", "and worn at once");
  assert.equal(timers.size, 0, "the explicit outfit cancels the timer");
  new Function("State", "Bridge", "withOutfit", "id", body).call({ wardrobe }, State, Bridge, withOutfit, "auto");
  assert.equal(timers.size, 1, "picking Auto again re-arms it");
});
