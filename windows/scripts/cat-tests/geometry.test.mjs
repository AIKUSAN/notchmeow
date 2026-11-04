import test from "node:test";
import assert from "node:assert/strict";
import {
  DETAIL_FULL_MIN, COMPACT_EAR_SCALE, CURSOR, EAR_FIT, FACE, FLAT_FILL, MOMO_WHITE, PASSES, badgeSide, cursorLook, detailLevel, detailOf,
  earFit, earScale, faceAngles, flatFillColors, layout, mkWarp, newPose, outlineSteps, pupilOffset, supPoints,
} from "../../src/cat/geometry.ts";
import { CAT_IDS, PRESETS, kittenOf } from "../../src/cat/presets.ts";
import { earTop, finite, load, near, same } from "./util.mjs";

const geo = load("geometry-cases.json");
const warp = load("warp-cases.json");
const pose = (o = {}) => ({ ...newPose(), ...o });
const presetOf = (cat, kitten) => (kitten ? kittenOf(PRESETS[cat]) : PRESETS[cat]);
const noW = (L) => { const { W, ...rest } = L; return rest; };

test("the detail switch is at head width 28, and the compact ears ease back to full size at Ø28", () => {
  assert.equal(DETAIL_FULL_MIN, geo.detail.fullMinD);
  for (const { D, detail } of geo.detail.cases) assert.equal(detailOf(D), detail, `Ø${D}`);
  assert.equal(COMPACT_EAR_SCALE, geo.earScale.compactMin);
  for (const { D, scale } of geo.earScale.cases) near(earScale(D), scale);
  assert.equal(outlineSteps(19.9), 72);
  assert.equal(outlineSteps(20), 200);
  assert.equal(badgeSide(true), -1);
  assert.equal(badgeSide(false), 1);
});

test("detailLevel is the fixture's, and flatFill is exactly !layout().full (A-0b, merged `6adf584`)", () => {
  for (const { D, override, level } of geo.detailLevels) {
    const what = `Ø${D} ${override ?? "by its width"}`;
    same(detailLevel(D, override), level, what);
    assert.equal(!layout(PRESETS.momo, pose(), 0, 0, D, { detail: override ?? undefined }).full, level.flatFill, `${what}: flatFill is !layout().full`);
  }
  assert.ok(geo.detailLevels.some((c) => c.override === "compact" && c.D >= DETAIL_FULL_MIN) && geo.detailLevels.some((c) => c.override === "full" && c.D < DETAIL_FULL_MIN), "an override beats the width, both ways");
});

test("the flat fills: FLAT_FILL and every coat's flat colours are the fixture's, and the point mask is 0.86 R by 0.54 R (A-0b, merged `6adf584`)", () => {
  same(FLAT_FILL, geo.flatFill, "FLAT_FILL");
  assert.deepEqual(FLAT_FILL.point, { rx: 0.86, ry: 0.54, alpha: 0.85 }, "tuned to the gradient it replaces, not the Mac draft's 0.5 by 0.34");
  assert.deepEqual(Object.keys(geo.flatColors), [...CAT_IDS]);
  for (const id of CAT_IDS) same(flatFillColors(PRESETS[id]), geo.flatColors[id], `the flat colours of ${id}`);
  assert.deepEqual(flatFillColors(PRESETS.latte).point, geo.flatColors.latte.point, "a point cat has its point colour");
  assert.equal(flatFillColors(PRESETS.shrimpy).point, null, "and any other coat has none");
  assert.equal(flatFillColors(PRESETS.momo).ruff, null, "a cat without a ruff has no ruff colour");
});

test("head and ruff outlines, Shrimpy's fluffy edge included, are the fixture's", () => {
  for (const o of geo.outline) {
    const pts = supPoints(o.rx, o.ry, o.n, o.dy, o.spike, o.count, o.steps, o.bend);
    same(o.indices.map((i) => pts[i]), o.points, o.name);
  }
  assert.deepEqual(supPoints(1.16, 0.92, 2.2, 0, 0.035, 14, 200), supPoints(1.16, 0.92, 2.2, 0, 0.035, 14, 200), "the fluff is fixed, not random");
});

test("layout (head, eyes, nose, mouth, ears, badge) is the fixture's at every size, coat and pose", () => {
  for (const a of geo.anchors) {
    const L = layout(presetOf(a.cat, a.kitten), pose(a.pose), a.cx, a.cy, a.D, { T: a.T, earScale: a.earScale, badgeSide: a.badgeSide });
    same(noW(L), a.layout, `${a.cat}${a.kitten ? " kitten" : ""} Ø${a.D}`);
  }
  assert.deepEqual(PASSES, geo.passes);
});

test("the face turn: angles, pupil travel, cursor curve, warp, eyes and head lean are the fixture's", () => {
  assert.deepEqual(FACE, warp.face);
  assert.deepEqual(CURSOR, warp.cursor.px);
  for (const c of warp.cursor.cases) same(cursorLook(c.dx, c.dy), { x: c.x, y: c.y }, `cursor ${c.dx},${c.dy}`);
  for (const c of warp.angles) same(faceAngles(pose(c)), { yf: c.yf, pf: c.pf, pt: c.pt, fa: c.fa }, `angles ${c.yaw},${c.pitch},${c.lift},${c.roll}`);
  for (const c of warp.pupil) same(pupilOffset(c.yaw, c.pitch, c.w, c.h), c.offset, `pupil ${c.yaw},${c.pitch}`);
  for (const c of warp.warp) {
    const W = mkWarp(PRESETS[c.cat], c.yf, c.pt, 1);
    same(c.probes.map(([x, y]) => W(x, y)), c.out, `warp ${c.cat} ${c.yaw},${c.pitch}`);
  }
  for (const c of warp.eyes) same(layout(PRESETS[c.cat], pose({ yaw: c.yaw }), 0, 0, 2 * PRESETS[c.cat].rx).eyes, c.eyes, `eyes ${c.cat} yaw ${c.yaw}`);
  for (const c of warp.head) {
    const L = layout(PRESETS[c.cat], pose({ yaw: c.yaw, pitch: c.pitch }), 0, 0, c.D);
    same({ head: L.head, bend: L.bend, ruff: L.ruff, nose: L.nose, mouth: L.mouth }, { head: c.head, bend: c.bend, ruff: c.ruff, nose: c.nose, mouth: c.mouth }, `head ${c.cat} ${c.yaw},${c.pitch}`);
  }
});

test("the rules the spec states in numbers", () => {
  assert.deepEqual([FACE.yaw, FACE.pitch, FACE.pitchDown, FACE.muzzle, FACE.nose, FACE.bend, FACE.lean], [0.82, 0.6, 0.32, 0.12, 0.05, 0.1, 0.08]);
  const L = layout(PRESETS.momo, pose({ badgeS: 1 }), 100, 50, 66);
  near(L.badge.x - L.head.x, 1.4 * L.R);
  near(L.head.y - L.badge.y, 0.92 * L.R);
  const left = layout(PRESETS.momo, pose({ badgeS: 1 }), 100, 50, 20, { badgeSide: badgeSide(true) });
  assert.ok(left.badge.x < left.head.x, "in the compact notch the badge is on the left");
  for (const yaw of [0.62, 1.2, 1.3]) assert.ok(layout(PRESETS.momo, pose({ yaw }), 0, 0, 66).eyes.every((e) => e.fx >= 0.55), `yaw ${yaw}: the near eye keeps 55 % of its width`);
  assert.equal(MOMO_WHITE.length > 50, true);
});

test("a head pushed past what it can show never gives NaN: the face fades, the nose and mouth go", () => {
  for (const cat of ["shrimpy", "momo", "button"]) for (const D of [0, 12, 66]) for (const p of [
    { yaw: 3 }, { yaw: -3 }, { pitch: 2 }, { pitch: -2 }, { roll: Math.PI }, { roll: 20 }, { lift: 6 }, { yaw: 1.6, pitch: 1, roll: 1 },
  ]) {
    const L = layout(PRESETS[cat], pose({ ...p, badgeS: 1 }), 10, 10, D);
    finite(noW(L), `${cat} Ø${D} ${JSON.stringify(p)}`);
    if (!L.nose.visible) assert.equal(L.mouth, null, "no nose, no mouth");
  }
  const over = layout(PRESETS.momo, pose({ roll: Math.PI }), 0, 0, 66);
  assert.equal(over.fa, 0, "rolled over the top: the face is gone");
  assert.equal(over.nose.visible, false);
  assert.equal(over.mouth, null);
  const away = layout(PRESETS.momo, pose({ yaw: 3 }), 0, 0, 66);
  assert.equal(away.eyes.every((e) => !e.visible), true);
});

// The ear fit is the contract's (A-0b, merged `6adf584`): the exact solve of the ear's top edge. It is checked here against a walk of the ear's whole
// outline (earTop), with the fixture's margin and minimum (not the module's, so the check cannot move with the code), and below against earFitCases.
const { margin: MARGIN, minimum: MIN } = geo.earFit;

test("ear fit: in the compact strip no ear tip leaves the top, a shrunk ear sits exactly on the margin, a calm cat keeps its ears, and it never gives a bad number", () => {
  let shrunk = 0;
  const tops = (L, s) => Math.min(...L.ears.map((e) => earTop(L, s, e)));
  // The compact island: the cat sits in the middle of a 32 px strip at Ø20 (a 24 px strip at Ø18 is a screen without a notch).
  for (const [strip, D] of [[32, 20], [24, 18]]) {
    for (const [earU, earF, oy, tilt] of [[1, 0, 0, 0], [1.4, 0, 0, 0], [1.4, 0, -0.26, 0], [1.22, 0, -0.26, 0], [1.4, 0, -0.3, 0.24], [1.4, 0, -0.3, -0.24], [1.1, 0.45, -0.1, 0.1]]) {
      const s = pose({ earU, earF, oy, tilt }), ek = earScale(D);
      for (const id of ["momo", "shrimpy", "noodle", "puff", "button"]) {
        const L = layout(PRESETS[id], s, 40, strip / 2, D, { earScale: ek }), f = earFit(L, s, 0);
        const where = `${id} strip ${strip} Ø${D} earU ${earU} earF ${earF} oy ${oy} tilt ${tilt}`;
        assert.ok(f >= MIN && f <= 1, `${where}: the factor is ${MIN} to 1, not ${f}`);
        const after = layout(PRESETS[id], s, 40, strip / 2, D, { earScale: ek * f });
        if (f === 1) assert.ok(tops(L, s) >= MARGIN - 1e-3, `${where}: an ear that was left alone pokes out at ${tops(L, s)}`);
        else {
          shrunk++;
          if (f > MIN + 1e-9) assert.ok(Math.abs(tops(after, s) - MARGIN) <= 1e-3, `${where}: the top of the ears is at ${tops(after, s)}, not on the margin ${MARGIN}`);
          else assert.ok(tops(after, s) > tops(L, s), `${where}: held at the minimum, the tips come down`);
        }
      }
    }
  }
  assert.ok(shrunk > 10, `the poses do need the fit (${shrunk} cases)`);
  const calm = pose({ earU: 1 });
  near(earFit(layout(PRESETS.momo, calm, 40, 16, 20, { earScale: earScale(20) }), calm, 0), 1);
  const high = earFit(layout(PRESETS.momo, calm, 40, 3, 20, { earScale: 1 }), calm, 0);
  assert.ok(high < 1 && high >= MIN, `a cat too close to the top gets smaller ears, not ${high}`);
  assert.equal(earFit(layout(PRESETS.momo, calm, 40, 16, 0), calm, 0), 1, "a head of width 0 has nothing to fit");
  const nan = pose({ tilt: NaN });
  assert.equal(earFit(layout(PRESETS.momo, nan, 40, 16, 20), nan, 0), 1, "a pose that is not a number gives 1: nothing to fit");
  for (const s of [pose({ sy: Infinity }), pose({ tilt: 20, earU: 9 })]) {
    const f = earFit(layout(PRESETS.momo, s, 40, 16, 20), s, 0);
    assert.ok(Number.isFinite(f) && f >= MIN && f <= 1, `a bad pose gives a usable factor, not ${f}`);
  }
});

test("ear fit, the contract's: EAR_FIT and every earFitCases row replay from their own inputs (A-0b, merged `6adf584`)", () => {
  assert.deepEqual(EAR_FIT, geo.earFit);
  assert.ok(geo.earFitCases.length >= 80);
  for (const c of geo.earFitCases) {
    const p = presetOf(c.cat, c.kitten), s = pose(c.pose), L = layout(p, s, c.cx, c.cy, c.D, { earScale: c.earScale });
    near(earFit(L, s, c.ceiling, c.margin, c.minimum), c.fit);
  }
  const fits = geo.earFitCases.map((c) => c.fit);
  assert.ok(fits.includes(1) && fits.includes(MIN) && fits.some((f) => f > MIN && f < 1), "the cases need no fit, the minimum and something in between");
});
