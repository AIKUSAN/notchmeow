import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { BADGE_RIGHT, KittenPool, drawKittens, kittenCatState } from "../../src/cat/kittendraw.ts";
import { cleanCatBlock } from "../../src/cat/display.ts";
import { catCfg } from "../../src/cat/engine.ts";
import { KITTEN_PLACES, kittenStep, kittenView } from "../../src/cat/kittens.ts";
import { createKittenStrip, kittenStripCount, pruneMiniBots, tickKittenStrips } from "../../src/cat/minibots.ts";
import { State } from "../../src/core/state.ts";
import { fakeCanvas, installBrowserStubs } from "./fake-canvas.mjs";

installBrowserStubs();
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");

// The kittens' drawing: each is a live kitten engine of its parent's coat, with the parent's collar and its own state; "+N" and "×N" are labels; no timer, no loop.
const K = (id, state = "working", born = 0) => ({ id, type: "", session: null, state, born, last: born, until: state === "leaving" ? 600 : null });
const spot = (o = {}) => ({ place: "bigExpanded", pill: "integration_claude", parentCat: "momo", color: "#8AB4F8", ox: 100, oy: 80, unit: 58, ...o });
const many = (n) => Array.from({ length: n }, (_, i) => K("k" + i, "working", i));

test("a kitten shows its own state, and a happy blink while it leaves", () => {
  assert.deepEqual(["working", "searching", "approval", "leaving", "bogus"].map(kittenCatState), ["working", "searching", "approval", "finished", "working"]);
});

test("each kitten is an engine of kittenOf(its parent's coat), made once and dropped when it has not been drawn for a while", () => {
  const pool = new KittenPool(), e = pool.get("a", "momo", "working");
  assert.deepEqual([e.p.kitten, e.p.base, e.isMini, e.state], [true, "momo", true, "working"]);
  assert.equal(pool.get("a", "momo", "searching"), e, "the same engine, put in its new state");
  assert.equal(e.state, "searching");
  assert.notEqual(pool.get("a", "ginger", "working"), e, "another parent coat, another kitten");
  assert.equal(pool.size, 2);
  for (let i = 0; i < 30; i++) pool.endFrame();
  assert.equal(pool.size, 2, "kept for 30 frames");
  pool.endFrame();
  assert.equal(pool.size, 0, "then gone");
});

test("a row under the big cat: three kittens and a +N, each with the parent's collar colour and its own state, drawn at the slots of the contract", () => {
  const pool = new KittenPool(), ctx = fakeCanvas(), list = [K("k0", "approval", 3), K("k1", "searching", 2), K("k2", "working", 1), K("k3", "leaving", 0)];
  const slots = drawKittens(ctx, pool, spot(), list, 1 / 60);
  assert.equal(slots.shown.length, 3);
  assert.equal(slots.more, 1);
  assert.equal(pool.size, 3);
  assert.deepEqual(ctx.seen.texts, ["+1"], "the overflow label");
  assert.ok(ctx.calls.createRadialGradient >= 3, "a cat each, with its coloured eyes");
  const states = slots.shown.map((q) => pool.get(`bigExpanded:integration_claude:${q.id}`, "momo", kittenCatState(q.state)).state);
  assert.deepEqual(states, ["approval", "searching", "working"]);
  assert.ok(slots.shown.every((q) => pool.get(`bigExpanded:integration_claude:${q.id}`, "momo", "working").collarColor === "#8AB4F8"), "the parent's collar colour");
  const leaving = drawKittens(fakeCanvas(), pool, spot(), [K("z", "leaving")], 1 / 60);
  assert.equal(pool.get(`bigExpanded:integration_claude:${leaving.shown[0].id}`, "momo", "finished").state, "finished", "a leaving kitten blinks happy");
});

test("the +N of a row starts right of the last kitten's state badge, and under the pair it sits in the row, not below it (it would cross the card's edge)", () => {
  const boxes = (place) => { const c = fakeCanvas(), r = []; c.roundRect = (...a) => r.push(a); drawKittens(c, new KittenPool(), spot({ place }), many(5), 1 / 60); return r.at(-1); };
  const { d, x0, step } = KITTEN_PLACES.bigExpanded, unit = 58, head = d * unit, lastX = 100 + (x0 + 2 * step) * unit, badgeRight = lastX + BADGE_RIGHT * head;
  const [x, y, , h] = boxes("bigExpanded");
  assert.ok(x >= badgeRight, `the label's left edge ${x} clears the third kitten's badge (${badgeRight})`);
  assert.equal(y + h / 2, 80 + 34, "in the row's line");
  const pair = boxes("pairExpanded");
  assert.ok(pair[0] >= 100 + step * unit + BADGE_RIGHT * head, `${pair[0]}: right of the third kitten's badge`);
  assert.equal(pair[1] + pair[3] / 2, 80 + 34, "in the row, so the card's bottom edge is not crossed");
});

test("the pair in the compact notch: no kittens, only the count of them all; the other places, an empty list and an unknown place", () => {
  const pool = new KittenPool(), ctx = fakeCanvas();
  const slots = drawKittens(ctx, pool, spot({ place: "pairCompact", unit: 20 }), many(3), 1 / 60);
  assert.deepEqual([slots.shown.length, slots.label?.text, pool.size, ctx.seen.texts], [0, "×3", 0, ["×3"]]);
  for (const place of ["bigCompact", "pairExpanded", "pill"]) {
    const c = fakeCanvas(), p = new KittenPool();
    assert.equal(drawKittens(c, p, spot({ place, unit: place === "pill" ? 28 : 20 }), many(5), 1 / 60).shown.length, place === "bigCompact" ? 2 : 3, place);
    assert.deepEqual(c.seen.texts, [place === "bigCompact" ? "+3" : "+2"], `${place}: the overflow`);
  }
  const none = fakeCanvas();
  drawKittens(none, new KittenPool(), spot(), [], 1 / 60);
  drawKittens(none, new KittenPool(), spot({ place: "bogus" }), many(4), 1 / 60);
  assert.deepEqual([none.calls.createRadialGradient, none.calls.fill, none.seen.texts], [undefined, undefined, []], "nothing is drawn");
});

test("a kitten of every coat, at the sizes of the places, draws only finite numbers", () => {
  for (const parentCat of ["shrimpy", "momo", "snow", "latte", "noodle"]) for (const place of ["bigExpanded", "bigCompact", "pairExpanded", "pill"]) for (const unit of [0, 20, 58]) {
    drawKittens(fakeCanvas(), new KittenPool(), spot({ place, parentCat, unit }), many(4), 0.05);
  }
});

const el = (tag) => ({ tag, style: { setProperty(k, v) { this[k] = v; } }, className: "", classes: new Set(), width: 0, height: 0, isConnected: true, parentElement: null, append() {}, getContext: () => fakeCanvas(),
  classList: { toggle(n, on) { if (on) this.owner.classes.add(n); else this.owner.classes.delete(n); } } });

test("the pill's strip: kittens at its trailing end, the pill's name makes room, they leave when they stop, and a strip that is gone is forgotten", () => {
  globalThis.document = { createElement: (t) => { const e = el(t); e.classList.owner = e; return e; } };
  globalThis.window = { devicePixelRatio: 1 };
  try {
    State.settings = { ...State.settings, cat: cleanCatBlock({ character: "ginger", displayMode: "perAgent", agentCats: { agent_gemini: "oreo" } }) };
    State.tasks = [{ id: "integration_claude", name: "Claude Code", color: "#F5F6F8", state: "working", stepIndex: 0, steps: [], source: "claudeCode", isIntegration: true }, { id: "agent_gemini", name: "gemini", color: "#8AB4F8", state: "idle", stepIndex: 0, steps: [], source: "agent", isIntegration: false }];
    State.focusId = "integration_claude";
    State.kittens = {};
    catCfg.character = undefined;
    const pill = el("div");
    pill.classList.owner = pill;
    const strip = createKittenStrip(State.tasks[1]);
    strip.parentElement = pill;
    assert.deepEqual([strip.className, strip.style.width, strip.style.height], ["pill-kits", "84px", "28px"]);
    tickKittenStrips(1 / 60);
    assert.equal(pill.classes.has("has-kits"), false, "no kitten, nothing drawn, the name where it was");
    const t = performance.now();
    for (let i = 0; i < 4; i++) State.kittenEvent("agent_gemini", { type: "start", id: "g" + i, t: t + i });
    tickKittenStrips(1 / 60);
    assert.equal(pill.classes.has("has-kits"), true);
    assert.ok(parseFloat(pill.style["--kit-w"]) > 56, `room for three kittens and the +N: ${pill.style["--kit-w"]}`);
    State.kittenEvent("agent_gemini", { type: "end", t: t + 10 });
    tickKittenStrips(1 / 60);
    assert.equal(pill.classes.has("has-kits"), false, "the parent stopped: they are gone");
    assert.equal(pill.style["--kit-w"], "0px");
    strip.isConnected = false;
    const before = kittenStripCount();
    tickKittenStrips(1 / 60);
    assert.equal(kittenStripCount(), before - 1, "a strip that is no longer in the document is forgotten");
  } finally {
    delete catCfg.character;
    delete globalThis.window;
    installBrowserStubs();
    pruneMiniBots();
  }
});

test("the island's layer: drawn by the frame loop only, in the place the mode and the size say, never in another expanded view, and cleared once when the last kitten goes", () => {
  const island = source("island/island.ts"), views = source("views/views.ts");
  assert.match(island, /this\.drawKittenLayer\(dt, greetingActive \|\| this\.peeking\(\)\);\s*tickMiniBots\(dt\);\s*tickKittenStrips\(dt\);/, "a project's peek covers the layer too (sub-project P)");
  assert.match(island, /const shown = !covered && State\.mode !== "hidden" && !this\.uploadActive && \(!expanded \|\| State\.view === "overview"\);/);
  assert.match(island, /const place = kittenPlaceOf\(cast\.mode, expanded\)/);
  assert.match(island, /if \(this\.kittensDrawn\) \{ ctx\.setTransform\(1, 0, 0, 1, 0, 0\); ctx\.clearRect/);
  assert.doesNotMatch(island + source("cat/kittendraw.ts") + source("cat/minibots.ts"), /setInterval|new Worker/, "no new timers or polling");
  assert.doesNotMatch(source("cat/kittendraw.ts"), /setTimeout|requestAnimationFrame/);
  assert.match(views, /createKittenStrip\(task\),\s*\);/, "buildPill appends the strip");
  assert.equal(kittenView(kittenStep([], { type: "start", id: "a", t: 1 }), 2).length, 1);
});

test("the layer's size is written once, from KITTEN_W and KITTEN_H, for the bitmap and the style; the CSS carries no copy of it", () => {
  const island = source("island/island.ts"), css = source("style.css");
  assert.match(island, /this\.kittenCanvas\.style\.width = `\$\{KITTEN_W\}px`;\s*this\.kittenCanvas\.style\.height = `\$\{KITTEN_H\}px`;/);
  assert.doesNotMatch(css.match(/#kitten-canvas \{[^}]*\}/)[0], /width|height/);
});

test("each doc block sits directly above the constant it documents: BADGE_RIGHT's, then IN_ROW's, with no block between a constant and its own", () => {
  assert.match(source("cat/kittendraw.ts"), /\/\*\* Where a kitten's state badge ends[^\n]*\*\/\nexport const BADGE_RIGHT = 0\.85;\n\/\*\* The places whose "\+N" sits in the row[^\n]*\*\/\nconst IN_ROW = new Set\(/);
});
