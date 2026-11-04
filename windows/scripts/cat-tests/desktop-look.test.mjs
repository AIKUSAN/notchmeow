import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// What the desktop cat shows (sub-project H, spec §2): the seams between the island's page and the desktop page, pinned by source.
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");

test("the brain tells the body what the cat looks like: the cast's coat, the effective state, the collar in the focused agent's colour, its agent's kittens, whether it works, sleeps or dances, and its size", () => {
  const b = source("island/desktop.ts");
  assert.match(b, /coat: cast\.big\.cat, state, collar: bigCatCollar\(state, State\.focusTask\?\.color\), kittens: pill \? State\.kittens\[pill\] \?\? \[\] : \[\], pill,/);
  assert.match(b, /dancing: shouldDance\(State\.musicPlaying, state, "compact"\), working: BUSY\.has\(state\), asleep: State\.asleep, size: desktopSizeOf\(State\.settings\.cat\.desktop\.size\), now: performance\.now\(\),\s*outfit: State\.outfit,/);
  const body = source("desktop/body.ts");
  assert.match(body, /const kittens = kittenView\(look\.kittens, now \+ this\.skew\)/, "the kittens' times are in the brain's clock");
  assert.match(body, /drawDesktopCat\(ctx, this\.engine, this\.pool, this\.lay, \{ coat: look\.coat, collar: look\.collar, kittens, lookX: gaze\.x, lookY: gaze\.y, dancing: look\.dancing, pill: look\.pill, outfit: look\.outfit \}, dt\);/);
  assert.match(body, /gaze = c && at && !look\.asleep \?/, "a sleeping cat does not watch the cursor");
  assert.match(body, /if \(now - this\.lastWake > WAKE_EVERY_MS\) \{ this\.lastWake = now; this\.say\(\{ k: "wake", why: "hover" \}\); \}/);
  assert.match(body, /if \(!this\.cursorPoll \|\| this\.cursorAsked \|\| this\.flight \|\| this\.carrying \|\| this\.dragging \|\| this\.away \|\| this\.look\?\.asleep\) return;/, "the cursor is asked for one question at a time, not while the cat is busy, and not at all where the system has none (Linux)");
  assert.match(body, /\.catch\(\(\) => \{\}\)\.finally\(\(\) => \{ this\.cursorAsked = false; \}\);/, "a rejected cursor question clears the flag too, or the cat would never ask again");
  assert.match(body, /if \(!this\.globalCursor\) this\.cursor = null;/, "where the system gives no cursor (Wayland) the cat looks ahead unless the pointer is over it");
});

test("waking a sleeping desktop cat: the body puts the engine in the state the island says, so the Playful style's waking zoomies play as they do in the notch, and a hover or a click tells the island", () => {
  const body = source("desktop/body.ts");
  assert.match(body, /this\.engine\.setState\(look\.state as StateName\)/);
  assert.match(source("cat/engine.ts"), /zoomies/);
  assert.match(body, /this\.say\(\{ k: "wake", why: "hover" \}\)/);
  assert.match(body, /this\.say\(\{ k: "wake", why: "click" \}\)/);
});

test("the ?dev page has the desktop panel: the mock desktop at three sizes", () => {
  const dev = source("cat/devdesktop.ts");
  assert.ok(dev.includes('"desktop-mock"'));
  assert.match(dev, /cfg: mockCfg \}\)/, "the mock's cats keep their own cfg, so the shared one dev.ts writes every tick cannot turn their collar off");
  assert.match(dev, /mockCfg\.collar = st\.collar \? "band" : "off";/, "the panel's Collar choice sets a real collar style, or no collar is drawn");
  assert.match(dev, /collar: st\.collar \? bigCatCollar\(want, COLLAR\) : null/, "the mock's collar goes through the brain's rule, so an idle or sleeping cat wears none");
  assert.match(source("cat/dev.ts"), /mountDesktopDev\(root, wrap, ticks\);/);
});
