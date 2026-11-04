import test from "node:test";
import assert from "node:assert/strict";
import { SMALL_EYE, SMALL_EYE_SHAPES, smallEye, usesSmallEye } from "../../src/cat/smalleye.ts";
import { PRESETS, kittenOf } from "../../src/cat/presets.ts";
import { finite, load, near, same } from "./util.mjs";

// The small coloured eye, replayed from tests/fixtures/cat/small-eye-cases.json (B-0), and the inputs a JSON file cannot hold. The black coats' eyes are bright (`cat`).
const fx = load("small-eye-cases.json");
const INK = ["line", "flat", "happy", "closed", "spiral", "heart", "star"];

test("the constants and the shape list are the fixture's", () => {
  same(SMALL_EYE, fx.constants, "SMALL_EYE");
  assert.deepEqual([...SMALL_EYE_SHAPES], fx.shapes);
});

test("usesSmallEye replays the fixture: the four resting shapes and the left eye of a wink; every expression stays ink", () => {
  assert.equal(fx.uses.length, 26);
  for (const c of fx.uses) assert.equal(usesSmallEye(c.shape, c.sd), c.out, `${c.shape} ${c.sd}`);
  for (const s of INK) for (const sd of [-1, 1]) assert.equal(usesSmallEye(s, sd), false, `${s} ${sd}`);
  for (const bad of ["bogus", "", "PILL", undefined, null, 7, {}]) assert.equal(usesSmallEye(bad, -1), false, String(bad));
  assert.equal(usesSmallEye("wink", undefined), false, "a wink with no side is not the left eye");
});

test("smallEye replays every row of the fixture: sizes, squints, gazes, expression scales, other shapes and hostile inputs", () => {
  for (const g of ["sizes", "squints", "gazes", "scales", "others", "hostile"]) {
    assert.ok(fx[g].length > 0, g);
    fx[g].forEach((c, i) => same(smallEye(c.shape, c.o), c.out, `${g} ${i}: ${c.shape} ${JSON.stringify(c.o)}`));
  }
  assert.deepEqual([fx.sizes.length, fx.squints.length, fx.gazes.length, fx.scales.length], [56, 72, 72, 20]);
});

test("smallEye replays the bright rows: the black coats get a flat eye with no rim and a thinner pupil, and the other coats and a hostile `cat` stay normal", () => {
  assert.deepEqual([...SMALL_EYE.bright], fx.bright);
  assert.equal(fx.brights.length, 6);
  fx.brights.forEach((c, i) => same(smallEye(c.shape, c.o), c.out, `brights ${i}: ${c.shape} ${JSON.stringify(c.o)}`));
});

test("only an exact coat id in the bright list is bright (another coat, another case, a padded id, text that is not a string and no cat are normal); a kitten of a black coat keeps it", () => {
  const normal = smallEye("pill", { R: 10 });
  assert.ok(normal && !normal.closed);
  assert.equal("flat" in normal, false, "a normal eye has no flat key");
  for (const cat of ["momo", "shrimpy", "Midnight", "MIDNIGHT", " midnight", "midnight ", "midnight\n", "", "mid", ["midnight"], { 0: "midnight" }, 7, null, undefined, true]) {
    same(smallEye("pill", { R: 10, cat }), normal, `cat ${JSON.stringify(cat)}`);
  }
  for (const cat of SMALL_EYE.bright) for (const kitten of [false, true]) {
    const b = smallEye("pill", { R: 10, cat, kitten }), n = smallEye("pill", { R: 10, kitten });
    assert.ok(b && n && !b.closed && !n.closed);
    assert.equal(b.flat, true, `${cat} kitten ${kitten}`);
    assert.equal(b.rim, 0);
    near(b.pupil.rx / n.pupil.rx, SMALL_EYE.brightPupil.w / SMALL_EYE.pupil.w);
    same({ iris: b.iris, light: b.light, pupilY: b.pupil.ry }, { iris: n.iris, light: n.light, pupilY: n.pupil.ry }, `${cat} kitten ${kitten}: only the pupil's width, the rim and the fill change`);
  }
});

test("a bright eye keeps the dot's round, dilated pupil and the closed line of a blink", () => {
  same(smallEye("dot", { R: 10, cat: "oreo" })?.pupil, smallEye("dot", { R: 10 })?.pupil, "the dot's pupil");
  const shut = smallEye("pill", { R: 10, open: 0.1 }), brightShut = smallEye("pill", { R: 10, open: 0.1, cat: "midnight" });
  assert.equal(shut?.closed, true);
  same(brightShut, shut, "a closed eye is the same line");
  assert.equal("flat" in (brightShut ?? {}), false);
});

test("a number that is not a number (NaN, an infinity, text) is the default, and nothing is ever NaN: what a JSON fixture cannot hold", () => {
  const plain = smallEye("pill", { R: 10 });
  for (const bad of [NaN, Infinity, -Infinity, "9", null, undefined, {}, []]) {
    same(smallEye("pill", { R: 10, es: bad, open: bad, yaw: bad, pitch: bad }), plain, `es, open, yaw and pitch ${String(bad)}`);
  }
  for (const bad of [NaN, Infinity, -Infinity, "9", null, undefined]) {
    const e = smallEye("pill", { R: bad });
    finite(e);
    same(e, smallEye("pill", { R: 0 }), `R ${String(bad)}`);
  }
  finite(smallEye("pill", { R: 1e300, es: 1e300 }));
  finite(smallEye("wide", { R: -5, es: -2, open: 7, yaw: 1e9, pitch: -1e9 }));
  same(smallEye("pill", null), smallEye("pill", { R: 0 }), "no options at all: R 0, a point of an eye");
  assert.equal(smallEye("pill", [])?.shape, "pill");
  assert.equal(smallEye("wink", { sd: 1, R: 10 }), null, "the right eye of a wink stays ink");
  assert.equal(smallEye("wink", { sd: "1", R: 10 })?.shape, "wink", "an sd that is not exactly 1 is the left eye");
});

test("the pupil never leaves the iris, at every squint, gaze, shape, kitten and expression scale", () => {
  for (const shape of ["pill", "wide", "dot", "tired", "wink"]) for (const kitten of [false, true]) for (const cat of [undefined, "midnight"]) for (const es of [0.5, 1, 1.5]) {
    for (let open = 0.25; open <= 1.001; open += 0.125) for (const yaw of [-2, -0.62, 0, 0.62, 2]) for (const pitch of [-1, -0.5, 0, 0.5, 1]) {
      const e = smallEye(shape, { sd: -1, R: 12, es, open, yaw, pitch, kitten, cat });
      if (!e || e.closed) continue;
      // The farthest point of the pupil ellipse from the iris's centre, inside the iris ellipse (a point test on the extreme corners).
      for (const [cx, cy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
        const x = e.pupil.x + cx * e.pupil.rx, y = e.pupil.y + cy * e.pupil.ry;
        assert.ok((x / e.iris.rx) ** 2 + (y / e.iris.ry) ** 2 <= 1 + 1e-9, `${shape} kitten ${kitten} cat ${cat} es ${es} open ${open} yaw ${yaw} pitch ${pitch}`);
      }
    }
  }
});

test("the floors hold at the smallest heads: a catchlight of 0.45 px and a rim of 0.5 px", () => {
  for (const R of [0, 1, 3, 5, 5.9, 6]) {
    const e = smallEye("pill", { R });
    if (e && !e.closed) { near(e.light.r, 0.45); near(e.rim, 0.5); }
  }
  const big = smallEye("pill", { R: 20 });
  assert.ok(big && !big.closed);
  near(big.light.r, 1.5);
  near(big.rim, 1);
});

test("a kitten's eye is the coat's, 1.2 wider and 1.32 taller: what kittenOf does to a kitten's eyes", () => {
  const cat = smallEye("pill", { R: 10 }), kit = smallEye("pill", { R: 10, kitten: true });
  assert.ok(cat && kit && !cat.closed && !kit.closed);
  near(kit.iris.rx / cat.iris.rx, SMALL_EYE.kitten.w);
  near(kit.iris.ry / cat.iris.ry, SMALL_EYE.kitten.h);
  const k = kittenOf(PRESETS.momo);
  near(k.eye.w / PRESETS.momo.eye.w, SMALL_EYE.kitten.w);
  near(k.eye.h / PRESETS.momo.eye.h, SMALL_EYE.kitten.h);
});
