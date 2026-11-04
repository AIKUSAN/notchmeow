import test from "node:test";
import assert from "node:assert/strict";
import { DESKTOP_SIZES, desktopKittenSlots } from "../../src/cat/desktop.ts";
import { HEAD_HIT_K, desktopWindowLayout, hitsCat, kittenSide } from "../../src/cat/desktopview.ts";
import { BADGE_RIGHT } from "../../src/cat/kittendraw.ts";
import { CAT_IDS } from "../../src/cat/presets.ts";
import { finite, near } from "./util.mjs";

// Where the desktop cat's window is and what in it takes the mouse (sub-project H).

test("the window is sized for the cat, its badge and its kittens, and no larger: every shape and the canvas are inside it, at every size, coat, count and side", () => {
  for (const size of Object.keys(DESKTOP_SIZES)) for (const coat of CAT_IDS) for (const n of [0, 1, 3, 4, 8]) for (const side of [1, -1]) {
    const L = desktopWindowLayout(size, coat, n, side), tag = `${size} ${coat} ${n} ${side}`;
    finite(L);
    for (const q of desktopKittenSlots(Array.from({ length: n }, (_, i) => ({ id: `k${i}` })), side).shown) {
      const edge = L.headX + side * (Math.abs(q.x) + q.d * BADGE_RIGHT) * L.D;
      assert.ok(edge >= -1e-9 && edge <= L.w + 1e-9, `${tag}: a kitten's state badge sticks out beside its head and is inside the window`);
    }
    assert.equal(L.D, DESKTOP_SIZES[size], tag);
    near(L.canvasW * 0.6, L.D);
    assert.ok(L.canvasX >= -1e-9 && L.canvasX + L.canvasW <= L.w + 1e-9, `${tag}: the canvas is inside`);
    assert.equal(L.canvasH, L.h, tag);
    near(L.headY, L.canvasW / 2 + L.overhang, 1);
    for (const c of L.shapes) assert.ok(c.x - c.r >= -1e-9 && c.x + c.r <= L.w + 1e-9 && c.y - c.r >= -1e-9 && c.y + c.r <= L.h + 1e-9, `${tag}: a hit circle ${JSON.stringify(c)} is inside the ${L.w}x${L.h} window`);
    assert.equal(L.shapes.length, 2 + Math.min(n, 3) + (n > 3 ? 1 : 0), tag);
    // No larger than needed: with no kittens the window is the canvas; with kittens it grows on their side only.
    if (n === 0) assert.ok(L.w >= Math.ceil(L.canvasW) && L.w <= Math.ceil(L.canvasW) + 3, `${tag}: the canvas, and at most a few px more for a wide badge`);
    else assert.ok(side === 1 ? L.headX <= Math.ceil(L.canvasW / 2) : L.w - L.headX <= Math.ceil(L.canvasW / 2) + 3, `${tag}: grows on the kittens' side only`);
  }
});

test("the layout is a mirror: a left side puts the kittens at the left and the window grows to the left", () => {
  const a = desktopWindowLayout("medium", "momo", 4, 1), b = desktopWindowLayout("medium", "momo", 4, -1);
  assert.equal(a.w, b.w);
  near(a.headX + b.headX, a.w, 1);
  const kitten = (L, i) => L.shapes[2 + i];
  near(kitten(a, 0).x - a.headX, -(kitten(b, 0).x - b.headX));
  assert.ok(kitten(a, 0).x > a.headX && kitten(b, 0).x < b.headX);
});

test("the three sizes scale: the same cat and kittens, Small 48, Medium 64, Large 96", () => {
  const [s, m, l] = ["small", "medium", "large"].map((z) => desktopWindowLayout(z, "shrimpy", 3, 1));
  near(m.w / s.w, 64 / 48, 0.05);
  near(l.w / m.w, 96 / 64, 0.05);
  assert.ok(s.w < m.w && m.w < l.w && s.h < m.h && m.h < l.h);
});

test("an unknown size, coat, count or side is Medium, Shrimpy, none and the right", () => {
  const base = desktopWindowLayout("medium", "shrimpy", 0, 1);
  for (const size of [undefined, null, "Large", 96, {}, "constructor"]) assert.deepEqual(desktopWindowLayout(size, "shrimpy", 0, 1), base, String(size));
  assert.deepEqual(desktopWindowLayout("medium", "nope", 0, 1), base, "an unknown coat is Shrimpy");
  assert.deepEqual(desktopWindowLayout("medium", 7, 0, 1), base);
  for (const n of [NaN, Infinity, -3, "4", null, undefined, {}]) assert.deepEqual(desktopWindowLayout("medium", "shrimpy", n, 1), base, `count ${String(n)}`);
  assert.equal(desktopWindowLayout("medium", "shrimpy", 99, 1).shapes.length, 6, "held to eight kittens: the head, the badge, three kittens and the +N");
  for (const side of [0, 2, "-1", null, NaN]) assert.deepEqual(desktopWindowLayout("medium", "shrimpy", 3, side), desktopWindowLayout("medium", "shrimpy", 3, 1), String(side));
});

test("only the cat takes the mouse: the head with its ears, the badge, the kittens; the corners of the window pass through", () => {
  const L = desktopWindowLayout("medium", "shrimpy", 3, 1);
  assert.ok(hitsCat(L.shapes, L.headX, L.headY));
  assert.ok(hitsCat(L.shapes, L.headX, L.headY - L.D * HEAD_HIT_K + 1), "the top of the head");
  assert.ok(hitsCat(L.shapes, L.shapes[1].x, L.shapes[1].y), "the badge");
  assert.ok(hitsCat(L.shapes, L.shapes[2].x, L.shapes[2].y), "a kitten");
  assert.equal(hitsCat(L.shapes, 0, 0), false, "the top-left corner");
  assert.equal(hitsCat(L.shapes, L.w - 1, 0), false, "the top-right corner");
  assert.equal(hitsCat(L.shapes, L.headX, L.h + 50), false, "outside the window");
  assert.equal(hitsCat(L.shapes, L.headX + L.D * HEAD_HIT_K + 3, L.headY, 0), false);
  assert.equal(hitsCat(L.shapes, L.headX + L.D * HEAD_HIT_K + 3, L.headY, 4), true, "slack widens it");
  assert.equal(hitsCat([], 1, 1), false);
});

test("the kittens are on the right in the left half of the screen and on the left in the right half", () => {
  assert.equal(kittenSide(100, 0, 1000), 1);
  assert.equal(kittenSide(499.9, 0, 1000), 1);
  assert.equal(kittenSide(500, 0, 1000), -1);
  assert.equal(kittenSide(2100, 1000, 2000), -1);
  assert.equal(kittenSide(1100, 1000, 2000), 1);
});
