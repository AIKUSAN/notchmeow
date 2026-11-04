import test from "node:test";
import assert from "node:assert/strict";
import { drawBehindPass, drawCat, drawFrontPass, drawHeadPass, frameOf, stillView } from "../../src/cat/renderer.ts";
import { hex } from "../../src/cat/base.ts";
import { earFit, earScale, layout, newPose } from "../../src/cat/geometry.ts";
import { CAT_IDS, PRESETS, kittenOf } from "../../src/cat/presets.ts";
import { fakeCanvas, installBrowserStubs } from "./fake-canvas.mjs";
import { earTop, load, near } from "./util.mjs";

installBrowserStubs();

test("every coat and every kitten draws at every size, plain and with fur lines, without a bad number", () => {
  for (const id of CAT_IDS) for (const kit of [false, true]) for (const D of [12, 20, 28, 44, 66]) for (const fur of [false, true]) {
    const ctx = fakeCanvas();
    const p = kit ? kittenOf(PRESETS[id]) : PRESETS[id];
    drawCat(ctx, stillView(p, newPose()), 100, 80, D, { fur, glow: true });
    assert.ok(ctx.calls.fill > 5, `${id} Ø${D}: something was drawn`);
  }
});

test("a cat that is turned, rolled or squashed past the normal range still draws only finite numbers", () => {
  for (const id of ["shrimpy", "momo", "latte", "button"]) for (const D of [0, 12, 66]) for (const s of [
    { yaw: 3 }, { yaw: -3 }, { pitch: 2 }, { roll: Math.PI }, { roll: 20 }, { lift: 6 }, { sx: 0 }, { open: 0 }, { es: 0 },
    { yaw: 1.6, pitch: 1, roll: 1, badgeS: 1, blush: 1, mouth: 1.3, tongue: 1, mround: 1, wavy: 1, smile: -3, mskew: 3, paws: 1 },
  ]) {
    const ctx = fakeCanvas();
    drawCat(ctx, stillView(PRESETS[id], { ...newPose(), ...s }), 50, 50, D, { fur: true });
  }
});

test("the renderer leaves where the cat was drawn, for hairballs and flying files", () => {
  const v = stillView(PRESETS.momo, newPose());
  assert.equal(v.base, null);
  drawCat(fakeCanvas(), v, 40, 30, 66);
  assert.deepEqual(v.base, { x: 40, y: 30, R: 66 / (2 * PRESETS.momo.rx) });
  assert.ok(v.mouthAt && Number.isFinite(v.mouthAt.x), "the mouth position is left for the next frame");
  assert.equal(v.at.D, 66);
});

test("the cat is drawn in three separate passes, behind the head, the head, in front of it, so outfits can sit on either side", () => {
  const v = () => stillView(PRESETS.shrimpy, newPose());
  const f = frameOf(v(), 100, 80, 66);
  const behind = fakeCanvas(), head = fakeCanvas(), front = fakeCanvas(), all = fakeCanvas();
  drawBehindPass(behind, f); drawHeadPass(head, f); drawFrontPass(front, f);
  drawCat(all, v(), 100, 80, 66);
  assert.equal(behind.calls.clip, undefined, "the behind pass has no face to clip");
  assert.ok(head.calls.clip >= 1, "the face is clipped to the head");
  assert.ok(front.calls.stroke > 30 && !(behind.calls.stroke > 30) && !(head.calls.stroke > 30), "the whiskers are in the front pass only");
  for (const name of ["fill", "stroke", "save", "restore", "translate", "quadraticCurveTo"]) {
    assert.equal(all.calls[name] || 0, (behind.calls[name] || 0) + (head.calls[name] || 0) + (front.calls[name] || 0), `${name}: drawCat is the three passes`);
  }
  assert.equal(all.calls.save, all.calls.restore, "every save is restored");
});

test("below Ø28 the cat is drawn with flat fills: no gradient for the head, ears, ruff, rim, crown or point; Ø28 and up shades them (A-0b, merged `6adf584`)", () => {
  const gradients = (ctx) => (ctx.calls.createLinearGradient || 0) + (ctx.calls.createRadialGradient || 0);
  for (const id of CAT_IDS) for (const kit of [false, true]) {
    const p = kit ? kittenOf(PRESETS[id]) : PRESETS[id];
    for (const D of [12, 20, 27]) {
      const ctx = fakeCanvas();
      drawCat(ctx, stillView(p, newPose()), 100, 80, D, { eyes: "ink" }); // the small coloured eyes have an iris gradient of their own: renderer-eyes.test.mjs
      assert.equal(gradients(ctx), 0, `${id}${kit ? " kitten" : ""} Ø${D}: flat fills, no gradient`);
      assert.ok(ctx.calls.fill > 5, `${id} Ø${D}: something was drawn`);
    }
    const full = fakeCanvas();
    drawCat(full, stillView(p, newPose()), 100, 80, 28);
    assert.ok(gradients(full) >= 3, `${id}${kit ? " kitten" : ""} Ø28: the full cat is shaded`);
  }
});

test("the flat fills are the contract's numbers and colours: each coat's flat colours, the crown band and the point mask (A-0b, merged `6adf584`)", () => {
  const geo = load("geometry-cases.json"), rgbOf = (c) => `rgb(${c.map(Math.round)})`;
  const drawn = (id, D) => { const ctx = fakeCanvas(); drawCat(ctx, stillView(PRESETS[id], newPose()), 100, 80, D); return ctx.seen; };
  for (const id of CAT_IDS) {
    const { head, ears, ruff } = geo.flatColors[id], flat = drawn(id, 20).fillStyles;
    assert.ok(flat.includes(rgbOf(head)), `${id}: the head is one flat colour`);
    for (const e of ears) assert.ok(flat.includes(rgbOf(e)), `${id}: an ear is one flat colour`);
    if (ruff) assert.ok(flat.includes(rgbOf(ruff)), `${id}: the ruff is one flat colour`);
    assert.ok(!drawn(id, 28).fillStyles.some((s) => s.startsWith("rgb(")), `${id} Ø28: shaded, no flat colour`);
  }
  const { crown, point } = geo.flatFill, R = (id, D) => D / (2 * PRESETS[id].rx);
  const ellipse = (seen, rx, ry) => seen.ellipses.some((a) => Math.abs(a[2] - rx) < 1e-9 && Math.abs(a[3] - ry) < 1e-9);
  for (const id of ["latte", "cloud"]) {
    const seen = drawn(id, 20);
    assert.ok(ellipse(seen, point.rx * R(id, 20), point.ry * R(id, 20)), `${id}: the point mask is ${point.rx} R by ${point.ry} R`);
    assert.ok(seen.fillStyles.includes(`rgba(${geo.flatColors[id].point.map(Math.round)},${point.alpha})`), `${id}: in its point colour at alpha ${point.alpha}`);
  }
  for (const id of ["shrimpy", "ginger", "silver"]) {
    const seen = drawn(id, 20);
    assert.ok(ellipse(seen, crown.rx * R(id, 20), crown.ry * R(id, 20)), `${id}: the crown band is ${crown.rx} R by ${crown.ry} R`);
    assert.ok(seen.fillStyles.includes(`rgba(${hex(PRESETS[id].stripe)},${crown.alpha})`), `${id}: in its stripe colour at alpha ${crown.alpha}`);
  }
});

test("the ears are fitted under the strip: with an earCeiling no tip leaves it, a shrunk ear sits exactly on the margin, and a calm cat keeps its ears", () => {
  let shrunk = 0;
  for (const id of ["momo", "shrimpy", "noodle", "puff", "button"]) for (const [earU, oy, tilt] of [[1, 0, 0], [1.4, 0, 0], [1.4, -0.26, 0], [1.22, -0.26, 0], [1.4, -0.3, 0.24], [1.4, -0.3, -0.24]]) {
    const s = { ...newPose(), earU, oy, tilt };
    const bare = frameOf(stillView(PRESETS[id], s), 40, 16, 20), fitted = frameOf(stillView(PRESETS[id], s), 40, 16, 20, { earCeiling: 0 });
    const ratio = fitted.L.ears[0].h / bare.L.ears[0].h;
    if (earU === 1 && oy === 0 && tilt === 0) assert.equal(ratio, 1, `${id}: a calm cat keeps its ears`);
    if (ratio < 1 - 1e-9) {
      shrunk++;
      const top = Math.min(...fitted.L.ears.map((e) => earTop(fitted.L, fitted.s, e)));
      if (ratio > 0.35 + 1e-6) assert.ok(Math.abs(top - 0.5) <= 1e-3, `${id} earU ${earU} oy ${oy} tilt ${tilt}: the top of the ears is at ${top}, not on the margin 0.5`);
    }
    for (const e of bare.L.ears) assert.ok(Number.isFinite(e.h), "no ceiling: the ears are the scaled ones");
  }
  assert.ok(shrunk > 5, `the hop pushes ears out of the strip, so the fit has work to do (${shrunk} cases)`);
});

test("every compact cat wears the compact ear scale, and the fit multiplies it: earScale(D) * f (A-0b, merged `6adf584`)", () => {
  const p = PRESETS.noodle, s = { ...newPose(), earU: 1.4, oy: -0.3, tilt: 0.24 };
  const earH = (D, o) => frameOf(stillView(p, s), 40, 16, D, o).L.ears[0].h, want = (D, ek) => layout(p, s, 40, 16, D, { earScale: ek }).ears[0].h;
  for (const D of [12, 20, 24, 27.999]) near(earH(D), want(D, earScale(D)));
  for (const D of [28, 44, 66]) near(earH(D), want(D, 1));
  near(earH(20, { detail: "full" }), want(20, 1));                        // drawn at full detail, a small cat keeps its full ears
  const f = earFit(layout(p, s, 40, 16, 20, { earScale: earScale(20) }), s, 0);
  assert.ok(f < 1 && f > 0.35, `this pose needs the fit: ${f}`);
  near(earH(20, { earCeiling: 0 }), want(20, earScale(20) * f));
});
