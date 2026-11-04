import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { drawBehindPass, drawCat, drawFrontPass, drawHeadPass, frameOf, stillView } from "../../src/cat/renderer.ts";
import { BotEngine } from "../../src/cat/engine.ts";
import { newPose } from "../../src/cat/geometry.ts";
import { outfitColor, outfitShapes, paintOutfit } from "../../src/cat/outfitdraw.ts";
import { outfitDigest, outfitGeometry } from "../../src/cat/outfit.ts";
import { OUTFIT_DRAWN, OUTFIT_IDS } from "../../src/cat/wardrobe.ts";
import { CAT_IDS, PRESETS, kittenOf } from "../../src/cat/presets.ts";
import { THEME } from "../../src/theme.generated.ts";
import { fakeCanvas, installBrowserStubs, pointCanvas } from "./fake-canvas.mjs";

installBrowserStubs();
const COL = "#8AB4F8";
const draw = (p, D, o = {}) => { const ctx = fakeCanvas(); drawCat(ctx, stillView(p, newPose()), 100, 80, D, { dpr: 2, ...o }); return ctx; };
const total = (ctx) => Object.values(ctx.calls).reduce((a, b) => a + b, 0);
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");

test("every outfit on every coat at every size from Ø12 up draws with only finite numbers, adds drawing, and leaves the context as it found it", () => {
  for (const id of CAT_IDS) for (const D of [12, 18, 20, 27, 28, 40, 66, 96]) for (const outfit of OUTFIT_DRAWN) {
    const p = PRESETS[id], bare = draw(p, D), worn = draw(p, D, { outfit });
    assert.ok(total(worn) > total(bare), `${id} Ø${D} ${outfit}: something was added`);
    assert.equal(worn.calls.save, worn.calls.restore, `${id} Ø${D} ${outfit}: every save is restored`);
  }
});

test("none, auto, no outfit and anything that is not an outfit draw exactly what a bare cat draws", () => {
  const p = PRESETS.momo, bare = draw(p, 40);
  for (const outfit of ["none", "auto", null, undefined, "", "fancyhat", "Bow", " bow", "__proto__", 7, {}, []]) assert.deepEqual(draw(p, 40, { outfit }).calls, bare.calls, JSON.stringify(outfit));
});

test("a kitten given any outfit stays bare; a mini engine draws the outfit it is given", () => {
  const strokes = (e, head) => { const ctx = fakeCanvas(); e.draw(ctx, head / 0.6, head / 0.6); return { n: total(ctx), strokeStyles: ctx.seen.strokeStyles.slice(), lineWidths: ctx.seen.lineWidths.slice() }; };
  const make = (outfit, p = PRESETS.momo) => { const e = new BotEngine(p, { cfg: { motion: "playful", override: {}, pers: {}, zoomAfter: 300000 }, quiet: true, now: () => 0, rand: () => 0.5, mini: true }); e.outfit = outfit; return e; };
  assert.equal(new BotEngine(PRESETS.momo, { quiet: true, now: () => 0, rand: () => 0.5 }).outfit, null, "an engine is bare until a view dresses it");
  for (const head of [13, 20, 24, 66]) {
    assert.ok(strokes(make("crown"), head).n > strokes(make(null), head).n, `Ø${head} an engine wears what it is given`);
    for (const outfit of ["none", "auto"]) assert.deepEqual(strokes(make(outfit), head), strokes(make(null), head), `Ø${head} ${outfit} draws as null`);
  }
  const kitten = kittenOf(PRESETS.momo);
  for (const outfit of OUTFIT_DRAWN) assert.deepEqual(strokes(make(outfit, kitten), 14), strokes(make(null, kitten), 14), `a kitten given ${outfit} draws what it draws bare`);
});

test("the outfit is drawn at the contract's three slots: bunny ears in the behind pass only, a scarf and a hat in the front pass only, the head untouched", () => {
  const view = () => stillView(PRESETS.shrimpy, newPose());
  const count = (outfit) => {
    const f = frameOf(view(), 100, 80, 66, { outfit, dpr: 2 }), behind = fakeCanvas(), head = fakeCanvas(), front = fakeCanvas();
    drawBehindPass(behind, f); drawHeadPass(head, f); drawFrontPass(front, f);
    return { behind: total(behind), head: total(head), front: total(front) };
  };
  const bare = count(null), ears = count("bunnyears"), scarf = count("scarf"), hat = count("crown");
  assert.ok(ears.behind > bare.behind && ears.front === bare.front && ears.head === bare.head, "bunny ears: behind only");
  assert.ok(scarf.front > bare.front && scarf.behind === bare.behind && scarf.head === bare.head, "scarf: front only");
  assert.ok(hat.front > bare.front && hat.behind === bare.behind && hat.head === bare.head, "crown: front only");
  const src = source("cat/renderer.ts");
  const collar = src.indexOf("if (G) drawCollar(c, G, o.collar.col, full, dpr);"), neck = src.indexOf('paintOutfit(c, f.outfit, "neck", f.edge); paintOutfit(c, f.outfit, "top", f.edge);'), whiskers = src.indexOf("// Whiskers rooted on the pad grid");
  assert.ok(collar > 0 && neck > collar && whiskers > neck, `${collar} < ${neck} < ${whiskers}: collar, outfit, whiskers`);
  const ears2 = src.indexOf("for (const ear of L.ears) drawEar(c, p, ear, R, full, flat);"), behindPaint = src.indexOf('paintOutfit(c, f.outfit, "behind", f.edge);');
  assert.ok(ears2 > 0 && behindPaint > ears2, "the behind slot is after the ears");
});

test("the coat is never recoloured, and every colour role the outfits use is in the theme", () => {
  const a = draw(PRESETS.latte, 40), b = draw(PRESETS.latte, 40, { outfit: "beanie" });
  for (const c of a.seen.fillStyles) assert.ok(b.seen.fillStyles.includes(c), `the coat's fill ${c} is still drawn`);
  const roles = new Set();
  for (const id of CAT_IDS) for (const outfit of OUTFIT_DRAWN) for (const D of [20, 66]) for (const col of [null, "tag", "band", "kerchief"]) for (const sh of outfitGeometry(outfit, PRESETS[id], newPose(), D, { dpr: 2, collar: col })) { if (sh.fill) roles.add(sh.fill); if (sh.stroke) roles.add(sh.stroke); }
  for (const r of roles) if (r !== "edge") assert.ok(Object.hasOwn(THEME.outfits, r) && /^#[0-9A-F]{6}$/i.test(THEME.outfits[r]), `${r} is a theme colour`);
  assert.equal(outfitColor("edge", "light"), THEME.outfits.edgeLight);
  assert.equal(outfitColor("edge", "dark"), THEME.outfits.edgeDark);
  assert.equal(outfitColor("gold", "dark"), THEME.outfits.gold);
  assert.equal(outfitColor("__proto__", "dark"), THEME.outfits.edgeDark, "a role the theme has not is the dark edge");
});

test("the notch gives a hat its room: with a ceiling the hat is shorter, without one it is natural, and the floor is kept", () => {
  const p = PRESETS.momo, s = newPose(), o = { dpr: 2 };
  // How far above the head's centre the highest point of the witch hat reaches (head-local px, up is smaller y), with the strip's top at `ceil` and the head at y 16.
  const reach = (ceil) => { const sh = outfitShapes("witchhat", p, s, 20, 16, ceil, o); assert.ok(sh && sh.length > 0, `drawn at ${ceil}`); return -outfitDigest(sh).bbox[1]; };
  const natural = reach(undefined), roomy = reach(-20), tight = reach(0), floor = reach(15.9);
  assert.equal(roomy, natural, "a ceiling out of reach changes nothing");
  assert.ok(tight < natural - 1, `a ceiling at the top of a 32 pt strip shortens the hat: ${tight} < ${natural}`);
  assert.ok(floor < tight && floor > 8.5, `no room at all is the floor's height, and the hat is still there: ${floor}`);
  assert.equal(outfitShapes("none", p, s, 20, 16, 0, o), null);
  assert.equal(outfitShapes("auto", p, s, 20, 16, 0, o), null);
  const compact = (ceiling) => { const ctx = fakeCanvas(); drawCat(ctx, stillView(p, newPose()), 40, 16, 20, { dpr: 2, outfit: "witchhat", earCeiling: ceiling, badgeSide: -1 }); return ctx; };
  assert.ok(total(compact(0)) > 0 && total(compact(undefined)) > 0, "the renderer passes the ears' ceiling through");
});

test("painting one slot touches only that slot, restores the state, and skips shapes of other slots", () => {
  const sh = outfitGeometry("scarf", PRESETS.momo, newPose(), 66, { dpr: 2 });
  assert.ok(sh.some((q) => q.slot === "neck"));
  const none = fakeCanvas(); paintOutfit(none, sh, "behind", "dark");
  assert.deepEqual(none.calls, {}, "no behind shape: nothing is even saved");
  const neck = fakeCanvas(); paintOutfit(neck, sh, "neck", "dark");
  assert.equal(neck.calls.save, 1); assert.equal(neck.calls.restore, 1);
  assert.equal(neck.calls.beginPath, sh.filter((q) => q.slot === "neck").length);
  assert.equal(OUTFIT_IDS.length, 18);
});

test("the dev mock's Ø96 cell, a cat in a canvas as tight as the panel's (top y 0, the cat at y 96 and Ø86.4), keeps the witch hat inside it on every coat", () => {
  for (const coat of CAT_IDS) {
    const c = pointCanvas();
    drawCat(c, stillView(PRESETS[coat], newPose()), 290, 96, 96 * 0.9, { tint: false, badge: false, outfit: "witchhat", outfitCeiling: 0, dpr: 2 });
    const top = Math.min(...c.points.map(([, y]) => y));
    assert.ok(top >= 0, `${coat}: the highest point of the drawing is at y ${top.toFixed(2)}`);
  }
});
