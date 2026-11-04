import test from "node:test";
import assert from "node:assert/strict";
import { COLLAR_MIN, COLLAR_PASS, COLLAR_STYLES, collarGeometry, collarStyleOf } from "../../src/cat/collar.ts";
import { PASSES, newPose } from "../../src/cat/geometry.ts";
import { CAT_IDS, PRESETS, kittenOf } from "../../src/cat/presets.ts";
import { finite, load, same } from "./util.mjs";

// The collar's geometry, replayed from tests/fixtures/cat/collar-cases.json (A-0b), and the facts the contract's own tests check.
const fx = load("collar-cases.json");
const geo = load("geometry-cases.json");
const pose = (o = {}) => ({ ...newPose(), ...o });
const STYLES = ["tag", "band", "kerchief"]; // the three that draw something; "off" draws nothing
const onHead = (pts, p, R, k = 1.02) => pts.every(([x, y]) => (x / (p.rx * R)) ** 2 + (y / (p.ry * R)) ** 2 <= k * k);

test("the four style IDs, the floors and the pass are the fixture's, and an unknown stored style is off", () => {
  assert.deepEqual([...COLLAR_STYLES], fx.styles);
  assert.deepEqual([...COLLAR_STYLES], ["tag", "band", "kerchief", "off"]);
  assert.deepEqual({ ...COLLAR_MIN }, fx.min);
  for (const r of fx.resolve) assert.equal(collarStyleOf(r.id), r.style, String(r.id));
  assert.equal(COLLAR_PASS, geo.collarPass);
  assert.deepEqual(PASSES, geo.passes, "PASSES is the line A-0 wrote");
  const front = PASSES[COLLAR_PASS];
  assert.equal(front.indexOf("whiskers"), front.indexOf("foldEars") + 1, "the collar's slot: between the folded ears and the whiskers");
});

test("every case of collar-cases.json replays from its own inputs: each style, at Ø12 to Ø66, at pixel ratio 1 and 2, at rest and with the head turned", () => {
  assert.ok(fx.cases.length >= 100);
  for (const k of fx.cases) {
    const p = k.kitten ? kittenOf(PRESETS[k.cat]) : PRESETS[k.cat];
    same(collarGeometry(p, pose(k.pose), k.D, k.style, { dpr: k.dpr }), k.out, `${k.cat}${k.kitten ? " kitten" : ""} ${k.style} D${k.D} dpr${k.dpr}`);
  }
  for (const style of STYLES) for (const D of [12, 20, 66]) for (const dpr of [1, 2]) assert.ok(fx.cases.some((k) => k.style === style && k.D === D && k.dpr === dpr), `${style} D${D} dpr${dpr} is in the fixture`);
  assert.ok(fx.cases.some((k) => k.style === "off" && k.out === null), "off is in the fixture");
});

test("the readability floors hold at Ø12 to Ø20 and at any pixel density: band 3 px, tag 6 px across, neckerchief 7 wide and 5 deep (device pixels)", () => {
  for (const dpr of [1, 2, 3]) for (const D of [12, 16, 20]) for (const style of STYLES) {
    const g = collarGeometry(PRESETS.shrimpy, pose(), D, style, { dpr });
    if (style !== "kerchief") assert.ok(g.width * dpr >= COLLAR_MIN.band - 1e-9, `band ${g.width * dpr} at D${D} dpr${dpr}`);
    if (style === "tag") assert.ok(g.tag.r * 2 * dpr >= COLLAR_MIN.tag - 1e-9, `tag at D${D} dpr${dpr}`);
    if (style === "kerchief") {
      const xs = g.kerchief.pts.map((q) => q[0]);
      assert.ok((Math.max(...xs) - Math.min(...xs)) * dpr >= COLLAR_MIN.kerchiefW - 1e-9, `kerchief width at D${D} dpr${dpr}`);
      assert.ok((g.kerchief.apex[1] - Math.max(...g.kerchief.pts.map((q) => q[1]))) * dpr >= COLLAR_MIN.kerchiefDrop - 1e-9, `kerchief drop at D${D} dpr${dpr}`);
    }
  }
});

test("off draws nothing, an unknown style is off, and each style has exactly its own parts", () => {
  for (const style of ["off", "scarf", "", null, undefined, 7, "follow"]) assert.equal(collarGeometry(PRESETS.momo, pose(), 40, style), null, String(style));
  const g = (style) => collarGeometry(PRESETS.momo, pose(), 40, style);
  assert.deepEqual(Object.keys(g("tag")).sort(), ["R", "band", "style", "tag", "width"]);
  assert.deepEqual(Object.keys(g("band")).sort(), ["R", "band", "style", "width"]);
  assert.deepEqual(Object.keys(g("kerchief")).sort(), ["R", "kerchief", "style"]);
  assert.equal(g("tag").band.length, 26);
  assert.ok(g("kerchief").kerchief.pts.length > 4);
  for (const style of STYLES) assert.equal(g(style).style, style);
});

test("large sizes scale with the head: the band a tenth of R, the tag 0.16 R, the neckerchief about 0.34 R deep", () => {
  const at = (style) => collarGeometry(PRESETS.momo, pose(), 66, style);
  assert.ok(Math.abs(at("band").width / at("band").R - 0.1) < 1e-9);
  assert.ok(Math.abs(at("tag").tag.r / at("tag").R - 0.16) < 1e-9);
  const k = at("kerchief"), drop = k.kerchief.apex[1] - Math.max(...k.kerchief.pts.map((q) => q[1]));
  assert.ok(drop >= 0.34 * k.R - 1e-9 && drop < 0.36 * k.R, `the drop is ${drop / k.R} R`);
});

test("every coat, style, pose and size, at either pixel density: the collar is finite and stays on the head", () => {
  for (const id of CAT_IDS) for (const style of STYLES) for (const s of [pose(), pose({ yaw: 0.6 }), pose({ yaw: -0.6, pitch: 0.4 }), pose({ pitch: -0.3 })]) for (const D of [12, 20, 28, 66]) for (const dpr of [1, 2]) {
    const g = collarGeometry(PRESETS[id], s, D, style, { dpr });
    finite(g, `${id} ${style} D${D}`);
    assert.ok(onHead(g.band || g.kerchief.pts, PRESETS[id], g.R), `${id} ${style} D${D} dpr${dpr}`);
  }
});

test("a head of width 0, or a bad pixel ratio, never produces NaN, and a bad ratio means 2", () => {
  for (const style of STYLES) {
    finite(collarGeometry(PRESETS.shrimpy, pose(), 0, style), `${style} at Ø0`);
    const two = collarGeometry(PRESETS.momo, pose(), 20, style, { dpr: 2 });
    for (const dpr of [NaN, 0, -1, undefined, null, "2"]) assert.deepEqual(collarGeometry(PRESETS.momo, pose(), 20, style, { dpr }), two, `${style} dpr ${dpr}`);
  }
});

test("the tag sits at centre front at rest and follows the face when the head turns; the pose is left alone", () => {
  const p = PRESETS.shrimpy, rest = collarGeometry(p, pose(), 66, "tag"), turned = collarGeometry(p, pose({ yaw: 0.6 }), 66, "tag");
  assert.ok(Math.abs(rest.tag.x) < 1e-9 && rest.tag.y > 0);
  assert.ok(turned.tag.x > rest.tag.x + 1, "the tag moves toward the side the face turned to");
  assert.ok(Math.abs(collarGeometry(p, pose(), 66, "kerchief").kerchief.apex[0]) < 1e-9, "the neckerchief points straight down at rest");
  const s = pose({ yaw: 0.3 }), before = JSON.stringify(s);
  assert.deepEqual(collarGeometry(PRESETS.momo, s, 28, "kerchief"), collarGeometry(PRESETS.momo, s, 28, "kerchief"));
  assert.equal(JSON.stringify(s), before);
});
