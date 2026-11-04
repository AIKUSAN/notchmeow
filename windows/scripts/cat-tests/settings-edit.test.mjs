import test from "node:test";
import assert from "node:assert/strict";
import { PERSONAS, personaNamed, slide } from "../../src/cat/personality.ts";
import * as S from "../../src/cat/settings.ts";

const plain = (v) => JSON.parse(JSON.stringify(v));
const deepFreeze = (v) => { if (v && typeof v === "object") { Object.values(v).forEach(deepFreeze); Object.freeze(v); } return v; };
/** The dotted paths at which two settings differ. */
function changed(a, b) {
  const out = [];
  const walk = (x, y, at) => {
    if (x && y && typeof x === "object" && typeof y === "object") for (const k of new Set([...Object.keys(x), ...Object.keys(y)])) walk(x[k], y[k], at ? `${at}.${k}` : k);
    else if (x !== y) out.push(at);
  };
  walk(plain(a), plain(b), "");
  return out;
}

test("each row changes exactly one thing, and the input is not touched (it is frozen here)", () => {
  const s = deepFreeze(S.defaultCatSettings());
  assert.deepEqual(changed(s, S.withCharacter(s, "momo")), ["character"]);
  assert.deepEqual(changed(s, S.withMotionStyle(s, "classic")), ["motionStyle"]);
  assert.deepEqual(changed(s, S.withCollar(s, "band")), ["collar"]);
  assert.deepEqual(changed(s, S.withFurLines(s, true)), ["furLines"]);
  assert.deepEqual(changed(s, S.withCatMotion(s, "momo", "classic")), ["cats.momo.motion"]);
  assert.deepEqual(changed(s, S.withCatCollar(s, "momo", "off")), ["cats.momo.collar"]);
  const sweet = changed(s, S.withPersonality(s, "ginger", personaNamed("sweet")));
  assert.ok(sweet.includes("cats.ginger.personality.preset") && sweet.every((p) => p.startsWith("cats.ginger.personality.")), sweet.join());
});

test("a bad value is the neutral one, so it changes nothing; an unknown cat is Shrimpy", () => {
  const s = deepFreeze(S.defaultCatSettings());
  assert.deepEqual(changed(s, S.withCharacter(s, "tiger")), []);
  assert.deepEqual(changed(s, S.withMotionStyle(s, "follow")), [], "follow is a per-cat word, not a global style");
  assert.deepEqual(changed(s, S.withCollar(s, "scarf")), []);
  assert.deepEqual(changed(s, S.withFurLines(s, 1)), [], "only a real true switches fur lines on");
  assert.deepEqual(changed(s, S.withCatMotion(s, "momo", "bogus")), [], "a bad override is follow");
  assert.deepEqual(changed(s, S.withPersonality(s, "momo", "not json")), [], "a personality that is not JSON is Balanced");
  assert.deepEqual(changed(s, S.withCatMotion(s, "tiger", "classic")), ["cats.shrimpy.motion"]);
});

test("moving a slider makes the cat's personality Custom with that trait changed, and the engine's config sees it", () => {
  let s = S.defaultCatSettings();
  s = S.withPersonality(s, "momo", personaNamed("chill"));
  assert.equal(s.cats.momo.personality.preset, "chill");
  s = S.withPersonality(s, "momo", slide(s.cats.momo.personality, "sass", 0.9));
  const { label: _label, ...chill } = PERSONAS.chill;
  assert.deepEqual(plain(s.cats.momo.personality), { preset: "custom", ...chill, sass: 0.9 }, "Custom, with the one trait moved and the others as they were");
  assert.equal(S.engineCfg(s).pers.momo.sass, 0.9);
  assert.equal(S.engineCfg(s).pers.ginger.preset, "balanced", "other cats keep theirs");
  s = S.withPersonality(s, "momo", personaNamed("sweet"));
  assert.equal(s.cats.momo.personality.preset, "sweet", "picking a preset again replaces the Custom values");
});

test("a whole session of edits ends where a person would expect", () => {
  let s = S.defaultCatSettings();
  s = S.withCharacter(s, "momo");
  s = S.withMotionStyle(s, "classic");
  s = S.withCatMotion(s, "momo", "playful");
  s = S.withPersonality(s, "momo", personaNamed("hyper"));
  s = S.withFurLines(s, true);
  s = S.applyToAllCats(s, "momo");
  assert.equal(s.character, "momo");
  assert.deepEqual(S.engineCfg(s).override, Object.fromEntries(Object.keys(s.cats).map((id) => [id, "playful"])));
  assert.ok(Object.values(s.cats).every((c) => c.personality.preset === "hyper"));
  assert.equal(S.motionFor(s, "ginger"), "playful", "every cat now has the override");
  assert.equal(s.motionStyle, "classic");
  assert.equal(s.furLines, true);
});
