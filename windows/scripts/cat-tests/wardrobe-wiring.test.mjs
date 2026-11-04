import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { BotEngine } from "../../src/cat/engine.ts";
import { drawDesktopCat } from "../../src/cat/desktopdraw.ts";
import { desktopWindowLayout } from "../../src/cat/desktopview.ts";
import { GT, GT2, Greeting, greetingDressed } from "../../src/cat/greeting.ts";
import { KittenPool } from "../../src/cat/kittendraw.ts";
import { PRESETS } from "../../src/cat/presets.ts";
import { fakeCanvas, installBrowserStubs } from "./fake-canvas.mjs";

// Who wears the outfit (sub-project I): the big cats, in every view that shows one, and nobody else. Behaviour where it can be run, source pins where the island's page cannot.
installBrowserStubs();
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const total = (ctx) => Object.values(ctx.calls).reduce((a, b) => a + b, 0);
const K = (id, state = "working") => ({ id, type: "", session: null, state, born: 0, last: 0, until: null });
const engine = () => new BotEngine(PRESETS.shrimpy, { quiet: true, now: () => 0, rand: () => 0.5 });
const look = (o = {}) => ({ coat: "momo", collar: "#8AB4F8", kittens: [], lookX: 0, lookY: 0, dancing: false, pill: "integration_claude", ...o });

test("the desktop cat wears the outfit it is told at every size, its kittens stay bare, and none or nothing draws what it drew before", () => {
  for (const size of ["small", "medium", "large"]) {
    const L = desktopWindowLayout(size, "momo", 0, 1), bare = fakeCanvas(), worn = fakeCanvas(), none = fakeCanvas(), e = engine();
    drawDesktopCat(bare, engine(), new KittenPool(), L, look(), 1 / 60);
    drawDesktopCat(worn, e, new KittenPool(), L, look({ outfit: "crown" }), 1 / 60);
    drawDesktopCat(none, engine(), new KittenPool(), L, look({ outfit: "none" }), 1 / 60);
    assert.ok(total(worn) > total(bare), `${size}: the crown is drawn`);
    assert.deepEqual(none.calls, bare.calls, `${size}: none draws nothing`);
    assert.equal(e.outfit, "crown");
  }
  const L = desktopWindowLayout("medium", "momo", 3, 1), pool = new KittenPool(), kittens = [K("a"), K("b"), K("c")];
  drawDesktopCat(fakeCanvas(), engine(), pool, L, look({ kittens, outfit: "witchhat" }), 1 / 60);
  for (const k of kittens) assert.equal(pool.get(`desktop:integration_claude:${k.id}`, "momo", "working").outfit, null, `kitten ${k.id} is bare`);
  const taken = fakeCanvas(); drawDesktopCat(taken, engine(), new KittenPool(), L, look({ kittens, outfit: null }), 1 / 60);
  const dressed = fakeCanvas(); drawDesktopCat(dressed, engine(), new KittenPool(), L, look({ kittens, outfit: "witchhat" }), 1 / 60);
  assert.ok(total(dressed) > total(taken), "the cat is dressed with its kittens beside it");
});

test("the greeting's cat is dressed once it has settled (or as the island folds, if that comes first), and the session cats never are", () => {
  assert.equal(greetingDressed(0), false);
  assert.equal(greetingDressed(GT2.back1 - 0.001), false);
  assert.equal(greetingDressed(GT2.back1), true);
  assert.equal(greetingDressed(GT.leave + 1), true);
  assert.equal(greetingDressed(1.0, 1.0), true, "the pointer left early: dressed as the island folds");
  assert.equal(greetingDressed(0.9, 1.0), false);
  const drawAt = (t, outfit, cast) => {
    globalThis.window = { setTimeout: () => 1, clearTimeout: () => {} };
    const g = new Greeting();
    g.start(cast, outfit);
    Object.defineProperty(g, "elapsed", { get: () => t });
    const ctx = fakeCanvas(); g.draw(ctx);
    return total(ctx);
  };
  for (const outfit of ["crown", "witchhat", "scarf", "bunnyears", "sunglasses"]) {
    assert.equal(drawAt(1.0, outfit), drawAt(1.0, null), `${outfit}: not dressed while it is still bouncing and waving`);
    assert.ok(drawAt(GT2.back1 + 0.1, outfit) > drawAt(GT2.back1 + 0.1, null), `${outfit}: dressed once settled`);
    assert.ok(drawAt(GT.leave + 0.6, outfit) > drawAt(GT.leave + 0.6, null), `${outfit}: and through the compact notch's tail`);
  }
  assert.equal(drawAt(GT2.back1 + 0.1, "none"), drawAt(GT2.back1 + 0.1, null), "none draws nothing");
  assert.equal(drawAt(GT2.back1 + 0.1, "crown", undefined), drawAt(GT2.back1 + 0.1, "crown", undefined), "deterministic");
});

test("the island dresses the main cat and cat 2, and no other engine: the mini bots, the kittens and the drop view's cat are bare", () => {
  const island = source("island/island.ts");
  assert.match(island, /this\.engine\.collarColor = bigCatCollar\(look\.state, focus\?\.color\);\s*this\.engine\.outfit = State\.outfit;/);
  assert.match(island, /this\.engine2\.collarColor = bigCatCollar\(state, task\?\.color\);\s*this\.engine2\.outfit = State\.outfit;/);
  assert.equal((island.match(/this\.\w*[eE]ngine\w*\.outfit = /g) || []).length, 2, "exactly two engines of the island are dressed");
  for (const rel of ["cat/minibots.ts", "cat/kittendraw.ts", "cat/kittens.ts", "upload/canvas.ts", "site/main.ts", "settings/display.ts", "cat/agentcat.ts"]) assert.ok(!/outfit/i.test(source(rel)), `${rel} gives no outfit`);
  assert.match(source("island/island.ts"), /this\.greeting\.start\(State\.cast\.greeting, State\.outfit\);/);
});

test("the greeting's session cats stay bare: their drawCat call names no outfit", () => {
  assert.match(source("cat/greeting.ts"), /drawCat\(x, this\.sessionViews\[i\] \?\? this\.minis, 0, 0, s\.d, \{ badge: false \}\);/, "the session cat is drawn with no outfit option");
});

test("the desktop cat's window is told the outfit by the brain and draws it, and the ?dev bench measures with one on", () => {
  assert.match(source("island/desktop.ts"), /size: desktopSizeOf\(State\.settings\.cat\.desktop\.size\), now: performance\.now\(\),\s*outfit: State\.outfit,/);
  assert.match(source("cat/desktoptrip.ts"), /outfit: string;/);
  assert.match(source("desktop/body.ts"), /dancing: look\.dancing, pill: look\.pill, outfit: look\.outfit \}, dt\);/);
  assert.match(source("cat/desktopdraw.ts"), /engine\.outfit = look\.outfit \?\? null;/);
  assert.ok(!/e\.outfit|engine\.outfit/.test(source("cat/desktopdraw.ts").split("const slots")[1]), "the kittens' engines are never dressed");
  assert.match(source("cat/devdesktop.ts"), /once\(id, 60, 3, "witchhat"\)/);
  assert.match(source("cat/devdesktop.ts"), /pill: "dev", outfit: st\.outfit \};/, "the mock desktop's cats can be dressed");
  assert.match(source("cat/dev.ts"), /greeting\.start\(undefined, dressed\.outfit\);/, "and so can the greeting's");
});
