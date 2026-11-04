import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { drawBehindPass, drawCat, drawFrontPass, drawHeadPass, frameOf, stillView } from "../../src/cat/renderer.ts";
import { newPose } from "../../src/cat/geometry.ts";
import { CAT_IDS, PRESETS, kittenOf } from "../../src/cat/presets.ts";
import { fakeCanvas, installBrowserStubs } from "./fake-canvas.mjs";

installBrowserStubs();
const STYLES = ["tag", "band", "kerchief"];
const COL = "#8AB4F8";
const draw = (p, D, collar, extra = {}) => { const ctx = fakeCanvas(); drawCat(ctx, stillView(p, newPose()), 100, 80, D, { collar, dpr: 2, ...extra }); return ctx; };
const total = (ctx) => Object.values(ctx.calls).reduce((a, b) => a + b, 0);

test("every coat and kitten wears every style at every size from Ø12 up, with only finite numbers, and it adds drawing", () => {
  for (const id of CAT_IDS) for (const kit of [false, true]) for (const D of [12, 16, 20, 28, 40, 66]) for (const style of STYLES) for (const dpr of [1, 2]) {
    const p = kit ? kittenOf(PRESETS[id]) : PRESETS[id];
    const bare = draw(p, D, null, { dpr }), worn = draw(p, D, { style, col: COL }, { dpr });
    assert.ok(total(worn) > total(bare), `${id}${kit ? " kitten" : ""} Ø${D} ${style}: something was added`);
    assert.ok((worn.calls.stroke || 0) > (bare.calls.stroke || 0), `${id} Ø${D} ${style}: it strokes an edge`);
    assert.equal(worn.calls.save, worn.calls.restore, "every save is restored");
  }
});

test("off, no collar and a colour that is not #RRGGBB draw nothing and never throw", () => {
  const p = PRESETS.momo, bare = draw(p, 40, undefined);
  for (const collar of [null, undefined, { style: "off", col: COL }, { style: "scarf", col: COL }, { style: "", col: COL }, { style: "tag", col: "red" }, { style: "tag", col: "#FFF" },
    { style: "band", col: "" }, { style: "band", col: "#GGGGGG" }, { style: "kerchief", col: 7 }, { style: "kerchief", col: null }, { style: "tag" }]) {
    assert.deepEqual(draw(p, 40, collar).calls, bare.calls, JSON.stringify(collar));
  }
});

test("the collar is in the front pass only: the behind pass and the head are drawn as without it", () => {
  const view = () => stillView(PRESETS.shrimpy, newPose());
  const count = (collar) => {
    const f = frameOf(view(), 100, 80, 66, { collar, dpr: 2 }), behind = fakeCanvas(), head = fakeCanvas(), front = fakeCanvas();
    drawBehindPass(behind, f); drawHeadPass(head, f); drawFrontPass(front, f);
    return { behind: total(behind), head: total(head), front: total(front) };
  };
  const bare = count(null), worn = count({ style: "tag", col: COL });
  assert.equal(worn.behind, bare.behind);
  assert.equal(worn.head, bare.head);
  assert.ok(worn.front > bare.front);
});

test("the collar sits between the folded ears and the whiskers (the contract's collarPass), and the coat is never recoloured", () => {
  const src = fs.readFileSync(new URL("../../src/cat/renderer.ts", import.meta.url), "utf8");
  const ears = src.indexOf("if (p.ear.fold) for (const ear of L.ears) drawEar(c, p, ear, R, full, flat, true);");
  const collar = src.indexOf("drawCollar(c, G, o.collar.col, full, dpr)");
  const whiskers = src.indexOf("// Whiskers rooted on the pad grid");
  assert.ok(ears > 0 && collar > ears && whiskers > collar, `${ears} < ${collar} < ${whiskers}`);
  const a = draw(PRESETS.latte, 28, null), b = draw(PRESETS.latte, 28, { style: "band", col: "#FF0000" });
  assert.deepEqual(b.seen.fillStyles, a.seen.fillStyles, "no fill of the coat changes: a band is stroked");
});

test("the readability floors reach the canvas: at Ø12 on a 1x screen the band is 3 px, on a 2x screen 1.5 CSS px, and its dark edge is 2 device px wider", () => {
  const widths = (dpr) => draw(PRESETS.shrimpy, 12, { style: "band", col: COL }, { dpr }).seen.lineWidths;
  assert.ok(widths(1).includes(3) && widths(1).includes(5), String(widths(1)));
  assert.ok(widths(2).includes(1.5) && widths(2).includes(2.5), String(widths(2)));
  assert.ok(draw(PRESETS.shrimpy, 12, { style: "tag", col: COL }, { dpr: 1 }).seen.strokeStyles.includes(COL), "the band is painted in the agent's colour");
});

test("without a dpr option the screen's pixel ratio is used, at most 2, and 1 outside a browser", () => {
  const band = (g) => { globalThis.devicePixelRatio = g; try { return draw(PRESETS.shrimpy, 12, { style: "band", col: COL }, { dpr: undefined }).seen.lineWidths; } finally { delete globalThis.devicePixelRatio; } };
  assert.ok(band(undefined).includes(3), "no ratio: 1");
  assert.ok(band(1.25).includes(3 / 1.25), "a 1.25 screen");
  assert.ok(band(3).includes(1.5), "a 3x screen is held to 2");
});
