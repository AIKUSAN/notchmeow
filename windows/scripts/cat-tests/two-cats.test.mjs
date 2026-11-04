import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { catCfg } from "../../src/cat/engine.ts";
import { GT, GT3, Greeting } from "../../src/cat/greeting.ts";
import { catClickTarget } from "../../src/core/layout.ts";
import { PRESETS } from "../../src/cat/presets.ts";
import { fakeCanvas, installBrowserStubs } from "./fake-canvas.mjs";

installBrowserStubs();
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");

// Two cats mode's layout: the glue is checked by source pins (it needs a browser), the greeting's pair arrival by drawing it.
const arrival = (cast, dt) => {
  globalThis.window = { setTimeout: () => 0, clearTimeout: () => {} };
  try {
    const clock = { t: 0 }, g = new Greeting(() => clock.t);
    g.start(cast);
    clock.t = (GT.leave + dt) * 1000;
    const ctx = fakeCanvas();
    g.draw(ctx);
    return ctx.seen.stops;
  } finally {
    delete globalThis.window;
  }
};
const MAIN = { cat: "ginger", sessions: ["ginger", "ginger", "ginger", "ginger"] };

test("the greeting's pair arrives together: the second cat pops in beside the settled one as the island folds, and not before, and not in the other modes", () => {
  const two = { ...MAIN, pair: ["shrimpy", "momo"] }, momo = PRESETS.momo.iris[0];
  assert.ok(!arrival(two, 0.1).includes(momo), "before the fold is under way: no second cat");
  assert.ok(!arrival(two, 0.2).includes(momo), "and not before the pop's own start");
  assert.ok(arrival(two, 0.5).includes(momo), "once it has popped in, cat 2 is drawn (Momo's eyes)");
  assert.ok(arrival(two, GT3.end - 0.05).includes(momo), "and it is there when the greeting hands over to the real pair");
  for (const none of [{ ...MAIN, pair: null }, MAIN, undefined]) assert.ok(!arrival(none, 0.5).includes(momo), "One cat and A cat for each agent greet with one cat");
  catCfg.character = "momo";
  assert.ok(arrival(undefined, 0.5).includes(momo), "(sanity: with Momo as the Main cat her eyes are drawn anyway)");
  delete catCfg.character;
});

test("the greeting's settled cat makes room for the pair, 10 px left, and only in Two cats mode; the numbers are the layout's", () => {
  const src = source("cat/greeting.ts");
  assert.match(src, /room = this\.pairView \? -\(40 - PAIR\.compact\.x1\) \* fold : 0/);
  assert.match(src, /drawCat\(x, this\.pairView, 320 - COMPACT \/ 2 \+ PAIR\.compact\.x2, 16, PAIR\.compact\.d \* pop, \{ badge: false, outfit: this\.outfit, outfitCeiling: 0 \}\)/);
  assert.match(src, /this\.pairView = cast\?\.pair \? this\.sessionView\(cast\.pair\[1\]\) : null;/);
});

test("the island: the second cat has its own canvas, engine and springs, only in Two cats mode, compact or in the overview, and its coat is the cast's", () => {
  const island = source("island/island.ts");
  assert.match(island, /const pair = this\.cast\.second \? pairPlacement\(State\.mode, State\.view, this\.height\.value\) : null;\s*const p = pair \? pair\.first : botPosition\(State\.mode, State\.view, this\.height\.value, State\.uploadProgress\);/, "One cat and A cat for each agent keep botPosition");
  assert.match(island, /this\.pairShown = pair !== null && visible;/);
  assert.match(island, /this\.engine2\.setCoat\(second\.cat\);\s*this\.engine2\.setState\(state\);/);
  assert.match(island, /this\.botCanvas,\s*this\.botCanvas2,/);
  assert.match(island, /if \(this\.pairShown\) this\.drawBot2\(dt\);/);
  assert.match(island, /\(this\.pairShown && \(this\.engine2\.busy \|\| !this\.bot2Cx\.settled/, "nothing keeps the loop alive while the island is hidden: pairShown is false then");
});

test("a click on the second cat focuses its agent, as a pill does, only while it is shown and has an agent", () => {
  const island = source("island/island.ts");
  assert.match(island, /const second = this\.cast\.second;\s*const hit = catClickTarget\(x, y, this\.botCircle\(\), second\?\.pill \? this\.bot2Circle\(\) : null\);\s*if \(hit === 2 && second\?\.pill\) \{\s*State\.setFocus\(second\.pill\);\s*Sound\.play\("blip"\);\s*return;\s*\}/);
  assert.match(island, /private bot2Circle\(\): Circle \| null \{\s*if \(!this\.pairShown\) return null;/);
});

test("where the two cats' hit circles overlap, the cat whose centre is nearer the click wins; a click in one circle goes to that cat", () => {
  const c1 = { cx: 40, cy: 40, r: 45 }, c2 = { cx: 114, cy: 40, r: 38 };
  assert.equal(catClickTarget(76.5, 40, c1, c2), 1, "inside both, nearer cat 1: the slap");
  assert.equal(catClickTarget(77.5, 40, c1, c2), 2, "inside both, nearer cat 2: the focus");
  assert.equal(catClickTarget(84, 40, c1, c2), 2, "the right edge of cat 1's head is inside cat 2's circle too");
  assert.equal(catClickTarget(77, 40, c1, c2), 1, "equal distance goes to cat 1");
  assert.equal(catClickTarget(150, 40, c1, c2), 2, "only in cat 2");
  assert.equal(catClickTarget(0, 40, c1, c2), 1, "only in cat 1");
  assert.equal(catClickTarget(300, 40, c1, c2), 0, "outside both");
  assert.equal(catClickTarget(80, 40, c1, null), 1, "no second cat: cat 1's circle only");
  assert.equal(catClickTarget(150, 40, c1, null), 0);
});

test("the overview: the ticker's text moves right of the pair and a second line names cat 2's agent; the other modes are untouched", () => {
  const views = source("views/views.ts"), css = source("style.css");
  assert.match(views, /el\.classList\.toggle\("two", two !== null\);/);
  assert.match(views, /`\$\{agentLabel\(other\.id\)\} · \$\{SECOND_LINE\[State\.shownState\(other\.state\)\]\}` : "No other agent"/);
  assert.match(views, /approval: "waiting for you", question: "has a question", error: "hit an error"/, "the prototype's word for a question is \"has a question\", and the Mac's ticker says the same");
  const from = css.lastIndexOf("/*", css.indexOf("Two cats mode (sub-project B)")), kit = css.indexOf("Subagent kittens (sub-project B)"), to = kit < 0 ? css.length : css.lastIndexOf("/*", kit);
  const block = css.slice(from, to).replace(/\/\*[\s\S]*?\*\//g, "");
  const selectors = [...block.matchAll(/([^{}]+)\{/g)].map((m) => m[1].trim());
  assert.deepEqual(selectors, ["#bot2-canvas", ".second", ".overview.two .who", ".overview.two .ticker", ".overview.two .int-card", ".overview.two .second"], "new selectors only; every existing rule applies as before outside `.overview.two`");
  assert.match(block, /\.overview\.two \.who \{\s*padding-left: 147px;/);
});

test("the dev server's fake-event path, for looking at the layout: window.__nm.hook feeds handleHook, behind import.meta.env.DEV, and a display mode in the address; nothing for a release build", () => {
  const main = source("main.ts");
  assert.match(main, /if \(import\.meta\.env\.DEV\) \(window as unknown as \{ __nm: unknown \}\)\.__nm = \{ island, State, hook: \(payload: HookPayload\) => handleHook\(island, payload\) \};/);
  assert.match(main, /if \(import\.meta\.env\.DEV\) \{\s*const mode = new URLSearchParams\(location\.search\)\.get\("display"\);\s*if \(mode\) State\.settings\.cat = withDisplayMode\(State\.settings\.cat, mode\);\s*\}/);
  assert.match(source("island/hooks.ts"), /export function handleHook\(island: Island, payload: HookPayload, stepBack\?: FocusMark\)/);
});
