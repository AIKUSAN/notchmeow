import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// An open island menu holds the island open like a pending card (sub-project I): the cursor poll keeps reporting the pointer outside the island while it is on the native menu, and
// that mouseLeft must not start the fold timer; the timer starts when the menu closes. The state machine is run here with a fake clock; the island's wiring is pinned by source.
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");

async function machine() {
  const live = new Map();
  let next = 1;
  globalThis.window = { setTimeout: (fn, ms) => { live.set(next, { fn, ms }); return next++; }, clearTimeout: (id) => live.delete(id) };
  const { IslandStateMachine } = await import("../../src/island/fsm.ts");
  const f = new IslandStateMachine();
  return { f, live, delays: () => [...live.values()].map((t) => t.ms) };
}

test("home: a mouseLeft while the menu is open starts no fold timer, and closing the menu with the pointer outside starts the home collapse", async () => {
  const { f, live, delays } = await machine();
  f.forceHome();
  f.mouseEntered();
  f.menuHold(true, true);
  f.mouseLeft(); // the cursor poll: the pointer is on the native menu, outside the island
  assert.equal(live.size, 0, "no fold timer while the menu is up");
  f.menuHold(false, false);
  assert.deepEqual(delays(), [f.homeToPetitDelay * 1000], "the home collapse starts when the menu closes");
  delete globalThis.window;
});

test("compact: the same holds against the petit hide", async () => {
  const { f, live, delays } = await machine();
  // The compact island hides only under a time setting (never is the default): one minute from a fixed last activity, so the timer is exact.
  f.now = () => 1000;
  f.lastActivity = 1000;
  f.tuckAway = "1";
  f.mouseEntered(); // hidden -> petit
  assert.equal(f.state, "petit");
  f.menuHold(true, true);
  f.mouseLeft();
  assert.equal(live.size, 0);
  assert.equal(f.state, "petit");
  f.menuHold(false, false);
  assert.deepEqual(delays(), [60 * 1000], "the tuck-away minute starts when the menu closes");
  delete globalThis.window;
});

test("a fold timer already running when the menu opens is cancelled, and closing the menu with the pointer back in the island starts none", async () => {
  const { f, live } = await machine();
  f.forceHome();
  f.mouseLeft();
  assert.equal(live.size, 1, "the pointer was out: the collapse is running");
  f.menuHold(true, false);
  assert.equal(live.size, 0, "opening the menu cancels it");
  f.menuHold(false, true);
  assert.equal(live.size, 0, "the pointer is on the island again: nothing to fold");
  delete globalThis.window;
});

test("the menu's hold is not the alert pin: it leaves the pin as it found it", async () => {
  const { f } = await machine();
  f.forceHome();
  f.pinned = true;
  f.menuHold(true, true);
  f.menuHold(false, true);
  assert.equal(f.pinned, true);
  delete globalThis.window;
});

test("the island holds from before the menu is shown until the native menu closes, whatever the way it closes", () => {
  const i = source("island/island.ts");
  assert.match(i, /this\.fsm\.menuHold\(true, this\.wasInIsland\);\s*try \{\s*await tickWardrobe\(parts\.wardrobe, State\.settings\.cat\.outfit\);\s*await parts\.menu\.popup\(\);\s*\} finally \{\s*this\.fsm\.menuHold\(false, this\.wasInIsland\);/);
  // the countdown bar is not armed while the menu is up either
  assert.match(i, /if \(this\.fsm\.state === "home" && !State\.isPinned && !this\.fsm\.menuOpen\) \{/);
});
