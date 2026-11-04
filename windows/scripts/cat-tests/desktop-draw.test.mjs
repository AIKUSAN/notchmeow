import test from "node:test";
import assert from "node:assert/strict";
import { BotEngine } from "../../src/cat/engine.ts";
import { drawDesktopCat } from "../../src/cat/desktopdraw.ts";
import { DESKTOP_SIZES } from "../../src/cat/desktop.ts";
import { desktopWindowLayout } from "../../src/cat/desktopview.ts";
import { KittenPool } from "../../src/cat/kittendraw.ts";
import { CAT_IDS, PRESETS } from "../../src/cat/presets.ts";
import { fakeCanvas, installBrowserStubs, pointCanvas } from "./fake-canvas.mjs";

installBrowserStubs();
const K = (id, state = "working", born = 0) => ({ id, type: "", session: null, state, born, last: born, until: state === "leaving" ? 600 : null });
const look = (o = {}) => ({ coat: "momo", collar: "#8AB4F8", kittens: [], lookX: 0, lookY: 0, dancing: false, pill: "integration_claude", ...o });
const engine = () => new BotEngine(PRESETS.shrimpy, { quiet: true, now: () => 0, rand: () => 0.5 });

test("the desktop cat is the big cat at full detail: one frame at every size and coat draws finite numbers, in the coat it is given, with the collar's colour", () => {
  for (const size of Object.keys(DESKTOP_SIZES)) for (const coat of CAT_IDS) {
    const ctx = fakeCanvas(), e = engine(), L = desktopWindowLayout(size, coat, 0, 1);
    drawDesktopCat(ctx, e, new KittenPool(), L, look({ coat, collar: "#22C55E" }), 1 / 60);
    assert.equal(e.p.name, coat, `${size} ${coat}`);
    assert.ok(ctx.calls.save >= 1 && ctx.calls.restore === ctx.calls.save, "balanced save and restore");
    assert.ok(Object.values(ctx.calls).reduce((n, c) => n + c, 0) > 100, "a cat was drawn");
  }
});

test("the engine is told what the desktop needs: the collar, no ear fit, the badge on the right, room for particles, and where to look", () => {
  const e = engine(), L = desktopWindowLayout("large", "shrimpy", 0, 1);
  e.earRoom = 5; e.badgeLeft = true;
  drawDesktopCat(fakeCanvas(), e, new KittenPool(), L, look({ coat: "shrimpy", collar: "#E879F9", lookX: 0.5, lookY: -0.5, dancing: true }), 1 / 60);
  assert.deepEqual([e.collarColor, e.earRoom, e.badgeLeft, e.particleOverhang, e.lookX, e.lookY, e.isDancing], ["#E879F9", null, false, L.overhang, 0.5, -0.5, true]);
  drawDesktopCat(fakeCanvas(), e, new KittenPool(), L, look({ coat: "nope", collar: null }), 1 / 60);
  assert.equal(e.collarColor, null);
  assert.equal(e.p.name, "shrimpy", "an unknown coat is Shrimpy");
});

test("up to three kittens are drawn beside the cat in its colour, then a +N, on the side the layout says; each is an engine of the cat's coat", () => {
  const list = [K("a", "approval", 3), K("b", "searching", 2), K("c", "working", 1), K("d", "leaving", 0), K("e", "working", 4)];
  for (const side of [1, -1]) {
    const pool = new KittenPool(), ctx = fakeCanvas(), L = desktopWindowLayout("medium", "momo", list.length, side);
    drawDesktopCat(ctx, engine(), pool, L, look({ kittens: list, collar: "#8AB4F8" }), 1 / 60);
    assert.equal(pool.size, 3, "three kittens are made");
    assert.deepEqual(ctx.seen.texts, ["+2"], `side ${side}`);
    const e = pool.get("desktop:integration_claude:a", "momo", "approval");
    assert.equal(e.collarColor, "#8AB4F8");
    assert.equal(e.p.base, "momo");
  }
  const none = fakeCanvas();
  drawDesktopCat(none, engine(), new KittenPool(), desktopWindowLayout("medium", "momo", 0, 1), look(), 1 / 60);
  assert.deepEqual(none.seen.texts, []);
});

test("a kitten engine nobody draws for 30 frames goes, and a cat with no kittens makes none", () => {
  const pool = new KittenPool(), L = desktopWindowLayout("medium", "momo", 1, 1);
  drawDesktopCat(fakeCanvas(), engine(), pool, L, look({ kittens: [K("a")] }), 0);
  assert.equal(pool.size, 1);
  for (let i = 0; i < 31; i++) drawDesktopCat(fakeCanvas(), engine(), pool, desktopWindowLayout("medium", "momo", 0, 1), look(), 0);
  assert.equal(pool.size, 0);
});

test("the desktop cat's Ø96 canvas keeps everything it draws inside the canvas, the witch hat included, on every coat", () => {
  for (const coat of CAT_IDS) {
    const c = pointCanvas(), e = engine(), L = desktopWindowLayout("large", coat, 0, 1);
    e.outfit = "witchhat";
    drawDesktopCat(c, e, new KittenPool(), L, look({ coat }), 1 / 60);
    const top = Math.min(...c.points.map(([, y]) => y));
    assert.ok(c.points.length > 0 && top >= 0, `${coat}: the highest point of the drawing is at y ${top.toFixed(2)}`);
  }
});
