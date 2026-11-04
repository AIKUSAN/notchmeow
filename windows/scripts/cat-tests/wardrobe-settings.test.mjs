import test from "node:test";
import assert from "node:assert/strict";
import { cleanCatBlock, defaultCatBlock, withCatSettings, withDesktopOn, withDisplayMode, withOutfit } from "../../src/cat/display.ts";
import { cleanCatSettings, withCollar } from "../../src/cat/settings.ts";
import { OUTFIT_IDS, cleanWardrobeSettings } from "../../src/cat/wardrobe.ts";
import { load } from "./util.mjs";

// The `outfit` key of the `cat` block (sub-project I): cleaned with the other three parts, kept by every edit of the others, and a fresh install is auto.
const fx = load("wardrobe-cases.json");

test("a fresh install holds auto, and every stored ID of the fixture comes through the block as written", () => {
  assert.equal(defaultCatBlock().outfit, "auto");
  assert.equal(cleanCatBlock(null).outfit, "auto");
  for (const id of OUTFIT_IDS) assert.equal(cleanCatBlock({ outfit: id }).outfit, id, id);
  for (const c of fx.settings) assert.deepEqual({ outfit: cleanCatBlock(c.input).outfit }, c.out, c.name);
  assert.deepEqual(cleanCatBlock({ outfit: "crown" }).outfit, cleanWardrobeSettings({ outfit: "crown" }).outfit);
});

test("a hand-edited or half-written outfit becomes auto and the rest of the block is untouched", () => {
  for (const bad of [7, null, true, [], ["bow"], {}, "Bow", " bow", "party-hat", "fancyhat", "", "__proto__"]) {
    const b = cleanCatBlock({ character: "momo", displayMode: "two", desktop: { on: true, size: "large" }, outfit: bad });
    assert.equal(b.outfit, "auto", JSON.stringify(bad));
    assert.deepEqual([b.character, b.displayMode, b.desktop.on, b.desktop.size], ["momo", "two", true, "large"], "the other parts are kept");
  }
  const block = cleanCatBlock({ outfit: "bow", collar: "band" });
  assert.deepEqual(cleanCatBlock(block), block, "cleaning twice changes nothing");
  assert.deepEqual(cleanCatBlock(JSON.parse(JSON.stringify(block))), block, "it survives JSON");
});

test("every other edit keeps the outfit, and the outfit edit keeps everything else", () => {
  const b = withOutfit(defaultCatBlock(), "santahat");
  assert.equal(b.outfit, "santahat");
  assert.equal(withCatSettings(b, withCollar(cleanCatSettings(b), "band")).outfit, "santahat", "a Cat settings row");
  assert.equal(withDisplayMode(b, "two").outfit, "santahat", "the Display row");
  assert.equal(withDesktopOn(b, true).outfit, "santahat", "the desktop cat's switch");
  const c = withOutfit(withDisplayMode(withDesktopOn(defaultCatBlock(), true), "two"), "none");
  assert.deepEqual([c.outfit, c.displayMode, c.desktop.on], ["none", "two", true]);
  assert.equal(withOutfit(b, "Crown").outfit, "auto", "a value that is not an ID is auto");
  assert.equal(withOutfit(b, undefined).outfit, "auto");
  assert.equal("outfit" in cleanCatSettings(b), false, "cleanCatSettings drops it: that is why the block has a clean-up of its own");
});
