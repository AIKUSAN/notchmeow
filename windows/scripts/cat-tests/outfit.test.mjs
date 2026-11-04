import test from "node:test";
import assert from "node:assert/strict";
import { newPose } from "../../src/cat/geometry.ts";
import { collarGeometry } from "../../src/cat/collar.ts";
import { OUTFIT_MIN, OUTFIT_ORDER, OUTFIT_SLOTS, outfitAnchors, outfitDigest, outfitEdge, outfitGeometry, outfitRoom } from "../../src/cat/outfit.ts";
import { OUTFIT_DRAWN } from "../../src/cat/wardrobe.ts";
import { CAT_IDS, PRESETS } from "../../src/cat/presets.ts";
import { PASSES } from "../../src/cat/geometry.ts";
import { finite, load, same } from "./util.mjs";

// The outfits' anchors and shapes, replayed from tests/fixtures/cat/wardrobe-cases.json (I-0).
const fx = load("wardrobe-cases.json");
const POSES = { rest: newPose(), turned: { ...newPose(), yaw: 0.6, pitch: 0.15 } };
/** The options a renderer would pass: the notch's strips give the compact cat its room above the crown (32 pt for the Ø20 cat, 24 pt for the Ø18 one on a screen without a notch). */
const opts = (p, s, D, extra = {}) => {
  const o = { dpr: 2, ...extra };
  if (fx.strips[D]) o.room = outfitRoom(outfitAnchors(p, s, D, o), fx.strips[D] / 2, 0);
  return o;
};

test("the slots, the draw order, the floors and every coat's edge are the fixture's, and PASSES is untouched", () => {
  assert.deepEqual([...OUTFIT_SLOTS], fx.slots);
  assert.deepEqual(OUTFIT_ORDER, fx.order);
  assert.deepEqual({ ...OUTFIT_MIN }, fx.min);
  for (const id of CAT_IDS) assert.equal(outfitEdge(PRESETS[id]), fx.edge[id], id);
  assert.equal(OUTFIT_ORDER.front.indexOf("outfit.neck"), OUTFIT_ORDER.front.indexOf("collar") + 1, "the neck slot is just after the collar");
  assert.equal(OUTFIT_ORDER.front.indexOf("outfit.top"), OUTFIT_ORDER.front.indexOf("outfit.neck") + 1);
  assert.equal(OUTFIT_ORDER.front.indexOf("whiskers"), OUTFIT_ORDER.front.indexOf("outfit.top") + 1, "the whiskers stay in front of every outfit");
  assert.deepEqual(OUTFIT_ORDER.behind.slice(0, -1), PASSES.behind);
});

test("the room above the crown: the fixture's rows, and none without a number", () => {
  for (const r of fx.rooms) same(outfitRoom({ top: { y: r.top } }, r.headY, r.ceiling), r.out, JSON.stringify([r.headY, r.ceiling]));
});

test("the anchors replay: four coats at Ø20, Ø28, Ø48 and Ø64, at rest and with the head turned", () => {
  const keys = Object.keys(fx.anchors);
  assert.equal(keys.length, 32);
  for (const k of keys) {
    const [cat, D, pose] = k.split("/");
    same(outfitAnchors(PRESETS[cat], POSES[pose], Number(D), { dpr: 2 }), fx.anchors[k], k);
  }
});

test("the shapes replay: every outfit on four pinned cases, the collar strips, the unknown IDs and the detail cut", () => {
  for (const [k, byOutfit] of Object.entries(fx.geometry)) {
    const [cat, D, pose] = k.split("/");
    for (const id of OUTFIT_DRAWN) same(outfitGeometry(id, PRESETS[cat], POSES[pose], Number(D), opts(PRESETS[cat], POSES[pose], Number(D))), byOutfit[id], `${k} ${id}`);
  }
  for (const [k, row] of Object.entries(fx.collars)) {
    const [id, style] = k.split("/");
    same(collarGeometry(PRESETS.momo, POSES.rest, 64, style, { dpr: 2 }), row.collar, `${k} collar`);
    same(outfitGeometry(id, PRESETS.momo, POSES.rest, 64, { dpr: 2, collar: style }), row.shapes, k);
  }
  for (const u of fx.unknown) assert.deepEqual(outfitGeometry(u.id, PRESETS.momo, POSES.rest, 64, { dpr: 2 }), u.out, String(u.id));
  for (const f of fx.fine) {
    assert.equal(outfitGeometry(f.id, PRESETS.momo, POSES.rest, 27, { dpr: 2 }).length, f.at27, `${f.id} at Ø27`);
    assert.equal(outfitGeometry(f.id, PRESETS.momo, POSES.rest, 28, { dpr: 2 }).length, f.at28, `${f.id} at Ø28`);
  }
  for (const row of fx.shrimpSwitch.rows) {
    const shapes = outfitGeometry("shrimpclip", PRESETS.momo, POSES.rest, row.D, opts(PRESETS.momo, POSES.rest, row.D)).map((sh) => [sh.k, sh.slot, sh.fill ?? null, sh.stroke ?? null, sh.fine]);
    assert.deepEqual(shapes, row.shapes, `the shrimp clip at Ø${row.D}`);
  }
  for (const r of fx.lensRims) {
    const lenses = outfitGeometry("sunglasses", PRESETS[r.cat], POSES.rest, 64, opts(PRESETS[r.cat], POSES.rest, 64)).filter((sh) => sh.k === "ellipse" && sh.fill === "lens").map((sh) => ({ stroke: sh.stroke, sw: sh.sw }));
    same(lenses, r.lenses, `${r.cat}'s lenses`);
    assert.equal(outfitEdge(PRESETS[r.cat]), r.edge);
  }
});

test("all 256 outfit and coat pairs at Ø18, Ø20, Ø48 and Ø64 digest as the fixture says", () => {
  const keys = Object.keys(fx.digests);
  assert.equal(keys.length, 16 * 16 * 4);
  for (const k of keys) {
    const [cat, id, D] = k.split("/");
    same(outfitDigest(outfitGeometry(id, PRESETS[cat], POSES.rest, Number(D), opts(PRESETS[cat], POSES.rest, Number(D)))), fx.digests[k], k);
  }
  assert.deepEqual(outfitDigest([]), { n: 0, pts: 0, bbox: [0, 0, 0, 0], mx: 0, my: 0 });
});

test("in the compact notch every outfit on every coat has only finite numbers, no line under its floor, and stays inside the strip", () => {
  for (const [D, strip] of [[20, 32], [18, 24]]) for (const cat of CAT_IDS) for (const id of OUTFIT_DRAWN) {
    const p = PRESETS[cat], shapes = outfitGeometry(id, p, POSES.rest, D, opts(p, POSES.rest, D));
    assert.ok(shapes.length > 0, `${cat} ${id} Ø${D} is drawn`);
    finite(shapes, `${cat} ${id} Ø${D}`);
    for (const sh of shapes) assert.ok(sh.k === "curve" || sh.stroke === null ? true : sh.sw >= OUTFIT_MIN.line / 2 - 1e-9, `${cat} ${id} Ø${D}: a stroke under the floor`);
    for (const sh of shapes) if (sh.k === "curve") assert.ok(sh.sw >= OUTFIT_MIN.line / 2 - 1e-9, `${cat} ${id} Ø${D}: a curve under the floor`);
    const top = outfitDigest(shapes).bbox[1] + strip / 2;
    assert.ok(top >= -1e-9, `${cat} ${id} Ø${D}: rises ${-top.toFixed(3)} px above the strip`);
  }
});

test("a pose the engine can reach, a bad option and a bad preset ID never throw or give NaN", () => {
  const p = PRESETS.shrimpy, wild = { ...newPose(), yaw: 1.4, pitch: -1, earU: 1.4, oy: -0.3, tilt: 0.24 };
  for (const id of OUTFIT_DRAWN) for (const D of [12, 18, 20, 27, 28, 40, 66, 96]) for (const o of [{}, { dpr: 1 }, { dpr: 0 }, { dpr: -3 }, { room: 0 }, { room: NaN }, { room: null }, { collar: "bogus" }, { collar: "tag" }, { collar: "kerchief" }, { earScale: 0.5 }]) {
    finite(outfitGeometry(id, p, wild, D, o), `${id} Ø${D} ${JSON.stringify(o)}`);
  }
});
