import test from "node:test";
import assert from "node:assert/strict";
import { drawCat, stillView } from "../../src/cat/renderer.ts";
import { layout, newPose } from "../../src/cat/geometry.ts";
import { smallEye } from "../../src/cat/smalleye.ts";
import { CAT_IDS, PRESETS, kittenOf } from "../../src/cat/presets.ts";
import { TAU } from "../../src/cat/base.ts";
import { fakeCanvas, installBrowserStubs } from "./fake-canvas.mjs";
import { near } from "./util.mjs";

installBrowserStubs();

// The compact cat's plain resting eyes are small coloured eyes (spec §4); the expression shapes, the full cat and `eyes: "ink"` keep the ink ones. The black coats'
// eyes are bright: a flat fill, no gradient and no rim.
const draw = (p, D, extra = {}, pose = {}, shape = "pill") => {
  const ctx = fakeCanvas(), v = stillView(p, { ...newPose(), ...pose });
  v.eyeShape = () => shape;
  drawCat(ctx, v, 100, 80, D, extra);
  return ctx;
};
const BRIGHT = ["midnight", "oreo", "mocha"];
const ellipseAt = (ctx, x, y, rx, ry) => ctx.seen.ellipses.some((a) => Math.abs(a[0] - x) < 1e-9 && Math.abs(a[1] - y) < 1e-9 && Math.abs(a[2] - rx) < 1e-9 && Math.abs(a[3] - ry) < 1e-9 && a[6] === TAU);
const linerStrokes = (ctx, p) => ctx.seen.strokeStyles.filter((s) => s === p.liner).length;
const radial = (ctx) => ctx.calls.createRadialGradient || 0;
const linear = (ctx) => ctx.calls.createLinearGradient || 0;

test("a compact cat's resting eyes are two coloured irises, one gradient each (the black coats' are flat: none), and nothing else in the head is shaded", () => {
  for (const id of CAT_IDS) for (const kit of [false, true]) for (const D of [12, 20, 27]) {
    const p = kit ? kittenOf(PRESETS[id]) : PRESETS[id];
    assert.equal(radial(draw(p, D)), BRIGHT.includes(id) ? 0 : 2, `${id}${kit ? " kitten" : ""} Ø${D}`);
    assert.equal(linear(draw(p, D)), 0, `${id} Ø${D}: the flat fills stay flat`);
  }
});
test("the black coats' eyes glow: one flat fill of the lighter iris colour for each eye, no gradient, no rim, the thinner pupil and the catchlight; a kitten of the coat too; the other coats keep their rim", () => {
  const lum = (h) => { const n = parseInt(h.slice(1), 16); return 0.2126 * ((n >> 16) & 255) + 0.7152 * ((n >> 8) & 255) + 0.0722 * (n & 255); };
  const want = { midnight: "#F7D45C", oreo: "#DDEB5A", mocha: "#F6C44C" };
  for (const id of BRIGHT) for (const kit of [false, true]) {
    const p = kit ? kittenOf(PRESETS[id]) : PRESETS[id], D = 20, R = layout(p, newPose(), 0, 0, D).R;
    const lighter = lum(p.iris[0]) >= lum(p.iris[1]) ? p.iris[0] : p.iris[1], what = `${id}${kit ? " kitten" : ""}`;
    assert.equal(lighter.toUpperCase(), want[id], `${what}: the lighter of the two iris colours is the contract's`);
    const g = smallEye("pill", { sd: -1, R, es: 1, open: 1, kitten: kit, cat: id });
    assert.ok(g && !g.closed && g.flat === true && g.rim === 0, `${what}: the geometry is bright`);
    const ctx = draw(p, D), ink = draw(p, D, { eyes: "ink" });
    assert.equal(radial(ctx), 0, `${what}: no gradient`);
    assert.equal(ctx.seen.fillStyles.filter((f) => f === lighter).length - ink.seen.fillStyles.filter((f) => f === lighter).length, 2, `${what}: one flat fill of the lighter colour for each eye`);
    assert.ok(ellipseAt(ctx, 0, 0, g.iris.rx, g.iris.ry), `${what}: the iris`);
    assert.ok(ellipseAt(ctx, g.pupil.x, g.pupil.y, g.pupil.rx, g.pupil.ry), `${what}: the thin pupil`);
    assert.ok(ctx.seen.fillStyles.includes("rgba(255,255,255,.92)"), `${what}: the catchlight is kept`);
    assert.equal(linerStrokes(ctx, p), linerStrokes(ink, p), `${what}: no rim is stroked in the liner colour`);
  }
  // A normal coat's rim is the one thing that strokes in the liner colour (for a coat whose liner is its ink colour the ink pills stroke in it too, so those cannot tell).
  const withRim = CAT_IDS.filter((id) => !BRIGHT.includes(id) && PRESETS[id].liner !== PRESETS[id].ink);
  assert.ok(withRim.includes("momo") && withRim.length >= 3, withRim.join());
  for (const id of withRim) assert.equal(linerStrokes(draw(PRESETS[id], 20), PRESETS[id]) - linerStrokes(draw(PRESETS[id], 20, { eyes: "ink" }), PRESETS[id]), 2, `${id}: a normal coat has a rim on each eye`);
});

test("eyes: ink keeps the old ink pills, and the full cat is the same with or without it", () => {
  for (const id of ["momo", "snow", "latte"]) {
    assert.equal(radial(draw(PRESETS[id], 20, { eyes: "ink" })), 0, `${id} Ø20 ink`);
    for (const D of [28, 44, 66]) assert.deepEqual(draw(PRESETS[id], D, { eyes: "ink" }).calls, draw(PRESETS[id], D).calls, `${id} Ø${D}: the option changes nothing at full detail`);
  }
});

test("the expression shapes stay ink: happy, closed, spiral, heart, star, line and flat have no iris, and a wink has one", () => {
  const withIris = draw(PRESETS.momo, 20), plain = radial(withIris);
  for (const shape of ["happy", "closed", "spiral", "heart", "star", "line", "flat"]) assert.equal(radial(draw(PRESETS.momo, 20, {}, {}, shape)), 0, shape);
  assert.equal(radial(draw(PRESETS.momo, 20, {}, {}, "wink")), 1, "the left eye of a wink is coloured, the right one an ink arc");
  assert.equal(plain, 2);
  for (const shape of ["wide", "dot", "tired"]) assert.equal(radial(draw(PRESETS.momo, 20, {}, {}, shape)), 2, shape);
});

test("the iris is the coat's: Momo's gold, and an odd-eyed coat has a second colour for the right eye", () => {
  const momo = draw(PRESETS.momo, 20).seen.stops;
  assert.deepEqual(momo, [...PRESETS.momo.iris, ...PRESETS.momo.iris]);
  const snow = draw(PRESETS.snow, 20).seen.stops;
  assert.deepEqual(snow, [...PRESETS.snow.iris, ...PRESETS.snow.irisR], "Snow: one blue eye, one gold, as at full size");
});

test("the iris, pupil and rim are the contract's geometry at the head's radius, and the pupil and catchlight are the theme's and white", () => {
  const p = PRESETS.momo, D = 20, R = layout(p, newPose(), 0, 0, D).R, g = smallEye("pill", { sd: -1, R, es: 1, open: 1, yaw: 0, pitch: 0, kitten: false });
  assert.ok(g && !g.closed);
  const ctx = draw(p, D), has = (x, y, rx, ry) => ctx.seen.ellipses.some((a) => Math.abs(a[0] - x) < 1e-9 && Math.abs(a[1] - y) < 1e-9 && Math.abs(a[2] - rx) < 1e-9 && Math.abs(a[3] - ry) < 1e-9 && a[6] === TAU);
  assert.ok(has(0, 0, g.iris.rx, g.iris.ry), "the iris");
  assert.ok(has(g.pupil.x, g.pupil.y, g.pupil.rx, g.pupil.ry), "the pupil");
  assert.ok(ctx.seen.fillStyles.includes("rgba(255,255,255,.92)"), "the catchlight is white at 0.92");
  assert.ok(ctx.seen.strokeStyles.includes(p.liner) && ctx.seen.lineWidths.some((w) => Math.abs(w - g.rim) < 1e-9), "the rim is the coat's liner colour at the contract's width");
  near(g.iris.rx, 0.21 * R, 1e-9);
  const kit = kittenOf(p), gk = smallEye("pill", { sd: -1, R: layout(kit, newPose(), 0, 0, D).R, es: 1, open: 1, kitten: true });
  assert.ok(gk && !gk.closed);
  const kctx = draw(kit, D);
  assert.ok(kctx.seen.ellipses.some((a) => Math.abs(a[2] - gk.iris.rx) < 1e-9 && Math.abs(a[3] - gk.iris.ry) < 1e-9), "a kitten's iris is its own, larger one");
});

test("a blink or a squint under 0.22 closes the eye to a line in the ink colour, with no iris", () => {
  const open = draw(PRESETS.momo, 20), shut = draw(PRESETS.momo, 20, {}, { open: 0.1 });
  assert.equal(radial(shut), 0);
  assert.ok(shut.seen.strokeStyles.includes(PRESETS.momo.ink), "the line is the coat's ink");
  assert.ok((shut.calls.quadraticCurveTo || 0) >= (open.calls.quadraticCurveTo || 0) + 2, "an arc for each eye");
  assert.equal(radial(draw(PRESETS.momo, 20, {}, { open: 0.22 })), 2, "0.22 is still open");
});

test("every coat and kitten, every resting shape, squint and gaze at the compact sizes draws only finite numbers", () => {
  for (const id of CAT_IDS) for (const kit of [false, true]) for (const D of [6, 12, 20, 27]) for (const shape of ["pill", "wide", "dot", "tired", "wink"]) {
    const p = kit ? kittenOf(PRESETS[id]) : PRESETS[id];
    for (const pose of [{}, { open: 0.3, yaw: 0.6, pitch: 0.5 }, { open: 0, es: 0 }, { es: 1.5, yaw: -0.62 }]) draw(p, D, {}, pose, shape);
  }
});
