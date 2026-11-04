import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { STATES, TINT } from "../../src/cat/base.ts";
import { BotEngine } from "../../src/cat/engine.ts";
import { PRESETS } from "../../src/cat/presets.ts";
import { settle } from "../../src/site/react.ts";
import { OUTFIT_DRAWN, OUTFIT_IDS, OUTFIT_NAMES } from "../../src/cat/wardrobe.ts";
import { REACTIONS, TRY_OUTFITS, nextOutfit, outfitWords } from "../../src/site/rules.ts";

const STATE_ORDER = ["working", "thinking", "approval", "question", "finished", "error", "ratelimit", "sleeping"];
const WORDS = ["Working", "Thinking", "Needs your OK", "Has a question", "Done", "Something failed", "Hit a limit", "Asleep"];

test("the reactions are the eight states of the brief, in order, and each one is a state the engine knows", () => {
  assert.deepEqual(REACTIONS.map((r) => r.state), STATE_ORDER);
  for (const r of REACTIONS) assert.ok(STATES.includes(r.state), r.state);
  assert.equal(new Set(REACTIONS.map((r) => r.state)).size, 8);
});

test("each button carries the words the brief gives it", () => {
  assert.deepEqual(REACTIONS.map((r) => r.label), WORDS);
});

test("each state has one plain sentence about what it means in the notch", () => {
  for (const r of REACTIONS) {
    assert.ok(r.line.length > 20 && r.line.endsWith("."), r.state);
    assert.doesNotMatch(r.line, new RegExp("coucou|" + "mo" + "chi", "i"), r.state);
  }
  assert.equal(new Set(REACTIONS.map((r) => r.line)).size, 8, "no two states share a sentence");
});

test("Try an outfit steps through the sixteen drawn outfits, then bare, and wraps round", () => {
  assert.equal(TRY_OUTFITS.length, 17);
  assert.deepEqual(TRY_OUTFITS.slice(0, 16), OUTFIT_DRAWN);
  assert.equal(TRY_OUTFITS[16], null, "the last step is bare");
  for (const id of TRY_OUTFITS) assert.ok(id === null || (OUTFIT_IDS.includes(id) && id !== "auto" && id !== "none"), String(id));
  assert.equal(nextOutfit(0), 1);
  assert.equal(nextOutfit(15), 16);
  assert.equal(nextOutfit(16), 0);
});

test("the outfit note names what the cat wears, or says it wears nothing", () => {
  assert.equal(outfitWords("partyhat"), "Wearing Party hat.");
  assert.equal(outfitWords(null), "Nothing on.");
  for (const id of OUTFIT_DRAWN) assert.equal(outfitWords(id), `Wearing ${OUTFIT_NAMES[id]}.`, id);
});

test("settle runs the engine on its own clock, so a reduced-motion still frame shows the state's badge", () => {
  const clock = { t: 0 };
  const e = new BotEngine(PRESETS.shrimpy, { now: () => clock.t, rand: () => 0.5 });
  e.setState("approval");
  assert.equal(e.badge, null, "the badge comes a moment after the state, on the clock");
  settle(e, clock);
  assert.equal(e.state, "approval");
  assert.equal(e.badge, "bang");
  assert.equal(e.s.tint, TINT.approval);
  assert.ok(clock.t >= 3000);
});

const page = fs.readFileSync(new URL("../../../docs/index.html", import.meta.url), "utf8");
const reactSection = page.match(/<section id="react"[^]*?<\/section>/)?.[0] ?? "";

test("the page has the section after What it does: its heading and the eight state buttons in order, the first pressed", () => {
  assert.ok(reactSection, "section#react");
  assert.ok(page.indexOf('id="what"') < page.indexOf('id="react"') && page.indexOf('id="react"') < page.indexOf('id="private"'));
  assert.match(reactSection, /<h2 id="react-h">How the cats react<\/h2>/);
  assert.match(reactSection, /aria-labelledby="react-h"/);
  const buttons = [...reactSection.matchAll(/<button type="button" data-state="([a-z]+)" aria-pressed="(true|false)">([^<]+)<\/button>/g)];
  assert.deepEqual(buttons.map((m) => m[1]), REACTIONS.map((r) => r.state));
  assert.deepEqual(buttons.map((m) => m[3]), REACTIONS.map((r) => r.label));
  assert.deepEqual(buttons.map((m) => m[2]), ["true", "false", "false", "false", "false", "false", "false", "false"]);
});

test("the sentence under the cat starts as the working state's, the cat is labelled, and Poke and Try an outfit are buttons", () => {
  assert.ok(reactSection.includes(`<p class="react-line" data-line aria-live="polite">${REACTIONS[0].line}</p>`));
  assert.match(reactSection, /<button type="button" class="react-cat" aria-label="Shrimpy: poke to say hello"><canvas aria-hidden="true"><\/canvas><\/button>/);
  assert.match(reactSection, /<button type="button" data-action="poke">Poke<\/button>/);
  assert.match(reactSection, /<button type="button" data-action="outfit">Try an outfit<\/button>/);
});

const react = fs.readFileSync(new URL("../../src/site/react.ts", import.meta.url), "utf8");
const main = fs.readFileSync(new URL("../../src/site/main.ts", import.meta.url), "utf8");

test("the section runs the app's engine on its own loop, only while it is on screen, and under reduced motion draws one still frame", () => {
  for (const need of ["new VisibleLoop(", "animates(page)", "new IntersectionObserver(", "prefers-reduced-motion", "setState(", 'emote("happy")', "engine.outfit = id", "settle(engine, clock)"]) assert.ok(react.includes(need), need);
  assert.doesNotMatch(react, /\bfetch\s*\(|localStorage|sessionStorage|document\.cookie|XMLHttpRequest|sendBeacon|AudioContext|https?:\/\//);
});

test("the page's entry starts the section, and nothing else in the page reads it", () => {
  assert.match(main, /import \{ startReactions \} from "\.\/react\.ts"/);
  assert.match(main, /startReactions\(/);
});
