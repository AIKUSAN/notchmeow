import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { defaultDesktopSettings } from "../../src/cat/desktop.ts";
import * as D from "../../src/cat/display.ts";
import { cleanCatSettings, withCharacter } from "../../src/cat/settings.ts";
import { load, same } from "./util.mjs";

// The desktop cat's settings live in the `cat` block of settings.json beside the Cat settings and the Display settings, and no clean-up of the block drops them (sub-project H).
const fx = load("desktop-cases.json");
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const SPOTS = { "0,0,1512,982": { x: 300, y: 400 }, "0,0,1512,982|1512,-100,2560,1440": { x: 2000, y: 800 } };

test("the block holds `desktop`: fresh installs get the cat at home, Medium, no spots; the Cat settings and Display settings are untouched by it", () => {
  const b = D.defaultCatBlock();
  same(b.desktop, defaultDesktopSettings(), "default");
  assert.deepEqual(cleanCatSettings(b), cleanCatSettings({ ...b, desktop: undefined }));
  assert.deepEqual(D.cleanCatBlock({ desktop: { on: true, size: "large", spots: SPOTS } }).desktop, { on: true, size: "large", spots: SPOTS });
  for (const c of fx.settingsCases) same(D.cleanCatBlock({ desktop: c.raw }).desktop, c.out, c.name);
  assert.deepEqual(D.cleanCatBlock({ desktop: SPOTS }).desktop, defaultDesktopSettings(), "a block whose desktop is the wrong shape is the default");
});

test("a block cleaned again, or through JSON, is the same block, and a hostile `desktop` never throws or leaks into the other keys", () => {
  const b = D.cleanCatBlock({ character: "momo", displayMode: "two", desktop: { on: true, size: "small", spots: SPOTS, extra: 1 } });
  assert.deepEqual(D.cleanCatBlock(b), b);
  assert.deepEqual(D.cleanCatBlock(JSON.parse(JSON.stringify(b))), b);
  assert.equal("extra" in b.desktop, false);
  for (const desktop of [undefined, null, 5, "on", [], [true], { on: "true" }, { size: "XL" }, { spots: "{not json" }, JSON.parse('{"spots":{"__proto__":{"x":1,"y":1}}}')]) {
    const out = D.cleanCatBlock({ character: "ginger", desktop });
    assert.equal(out.character, "ginger");
    assert.deepEqual(Object.keys(out.desktop).sort(), ["on", "size", "spots"]);
  }
});

test("an edit of the Cat settings, of the Display settings or of the desktop each keep the other two parts", () => {
  const start = D.withDesktopOn(D.withDesktopSize(D.withDisplayMode(D.defaultCatBlock(), "two"), "large"), true);
  assert.deepEqual([start.desktop.on, start.desktop.size, start.displayMode], [true, "large", "two"]);
  const edited = D.withCatSettings(start, withCharacter(start, "momo"));
  assert.deepEqual([edited.character, edited.desktop, edited.displayMode], ["momo", start.desktop, "two"]);
  const shown = D.withDisplayMode(start, "perAgent");
  assert.deepEqual([shown.desktop, shown.character], [start.desktop, start.character]);
  const sized = D.withDesktopSize(start, "small");
  assert.deepEqual([sized.desktop.size, sized.desktop.on, sized.displayMode], ["small", true, "two"]);
  assert.equal(D.withDesktopSize(start, "Huge").desktop.size, "medium", "an unknown size is Medium");
  assert.equal(D.withDesktopOn(start, false).desktop.on, false);
  assert.equal(D.withDesktopOn(start, 1).desktop.on, false, "only the boolean true is on");
  const spotted = D.withDesktopSpots(start, SPOTS);
  assert.deepEqual(spotted.desktop.spots, SPOTS);
  assert.deepEqual(D.withDesktopSpots(spotted, { nope: { x: 1, y: 1 } }).desktop.spots, {}, "a key that is not a screen arrangement is dropped");
  assert.deepEqual(Object.keys(start).sort(), Object.keys(D.defaultCatBlock()).sort());
});

test("the edits never touch their input", () => {
  const b = Object.freeze(D.defaultCatBlock());
  const before = JSON.stringify(b);
  D.withDesktopOn(b, true); D.withDesktopSize(b, "small"); D.withDesktopSpots(b, SPOTS); D.withDesktop(b, { on: true });
  assert.equal(JSON.stringify(b), before);
});

test("State starts with the default block, and the Settings window and the island both clean the whole block", () => {
  assert.match(source("core/state.ts"), /cat: defaultCatBlock\(\),/);
  assert.match(source("settings/app.ts"), /cat: cleanCatBlock\(s\.cat\)/);
  assert.match(source("island/island.ts"), /const block = cleanCatBlock\(State\.settings\.cat\);/);
});

test("Settings → Cat has the 'Cat on the desktop' switch in the Desktop card, built from the window's own row and switch, saving through withCatSettings", () => {
  const cat = source("settings/cat.ts");
  assert.match(cat, /row\("Cat on the desktop", desktop, /);
  assert.match(cat, /onclick: \(\) => change\(withDesktopOn\(host\.cat\(\), !host\.cat\(\)\.desktop\.on\)\)/);
  assert.match(cat, /desktop\.classList\.toggle\("on", out\);/);
  const at = (t) => cat.indexOf(t);
  assert.ok(at("Main cat: the cat of One cat mode") < at('card("Desktop"') && at('card("Desktop"') < at('row("Cat on the desktop"'), "in the Desktop card, after the Main cat hint");
});
