import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { StopTimers } from "../../src/island/stoptimers.ts";
import { CLICK_GUARD_MS, ClickGuard } from "../../src/views/clickguard.ts";

const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");

/** A timer queue the test turns by hand. */
function queue() {
  const q = { t: 0, id: 1, timers: new Map(), sets: 0, clears: 0 };
  q.env = {
    set: (fn, ms) => { const id = q.id++; q.sets++; q.timers.set(id, { fn, at: q.t + ms }); return id; },
    clear: (id) => { q.clears++; q.timers.delete(id); },
  };
  q.advance = (ms) => {
    const end = q.t + ms;
    for (const [id, x] of [...q.timers.entries()].sort((a, b) => a[1].at - b[1].at)) if (x.at <= end) { q.timers.delete(id); x.fn(); }
    q.t = end;
  };
  return q;
}

test("a Stop's return to idle fires once, after its delay", () => {
  const q = queue(), stops = new StopTimers(q.env);
  let idle = 0;
  stops.arm("integration_claude", 5200, () => idle++);
  assert.equal(stops.has("integration_claude"), true);
  q.advance(5199); assert.equal(idle, 0);
  q.advance(1); assert.equal(idle, 1);
  assert.equal(stops.has("integration_claude"), false, "the entry is gone once it has fired");
  q.advance(60_000); assert.equal(idle, 1);
});

test("the next turn cancels the return, so the pill is not flipped to idle in the middle of it", () => {
  const q = queue(), stops = new StopTimers(q.env);
  let idle = 0;
  stops.arm("integration_claude", 5200, () => idle++);
  q.advance(3000);
  assert.equal(stops.cancel("integration_claude"), true);
  q.advance(10_000);
  assert.equal(idle, 0);
  assert.equal(stops.cancel("integration_claude"), false, "nothing left to cancel");
});

test("a second Stop for the same pill replaces the first; another pill's timer is not touched", () => {
  const q = queue(), stops = new StopTimers(q.env);
  const fired = [];
  stops.arm("a", 5200, () => fired.push("a1"));
  stops.arm("b", 5200, () => fired.push("b"));
  q.advance(2000);
  stops.arm("a", 5200, () => fired.push("a2"));
  assert.equal(q.clears, 1, "only a's first timer was cleared");
  stops.cancel("zzz");
  q.advance(3200);
  assert.deepEqual(fired, ["b"], "b fired at 5200, a's second timer is 2000 ms behind");
  q.advance(2000);
  assert.deepEqual(fired, ["b", "a2"]);
});

test("the click guard ignores the first 600 ms of a new request and no more", () => {
  const g = new ClickGuard();
  assert.equal(CLICK_GUARD_MS, 600);
  g.shown("req-1", 1000);
  assert.equal(g.blocks(1000), true);
  assert.equal(g.blocks(1599), true);
  assert.equal(g.blocks(1600), false);
  g.shown("req-1", 5000);          // the same request drawn again (every sync): the clock does not restart
  assert.equal(g.blocks(5000), false);
  g.shown("req-2", 6000);          // a different request starts it again
  assert.equal(g.blocks(6300), true);
  assert.equal(g.blocks(6600), false);
});

test("a guard that has seen no request blocks nothing once 600 ms of the page's life have passed", () => {
  const g = new ClickGuard();
  assert.equal(g.blocks(100_000), false);
});

test("the wiring: hooks.ts cancels the Stop timer on the next turn, and the approval buttons go through the guard", () => {
  const hooks = source("island/hooks.ts");
  assert.match(hooks, /new StopTimers\(\)/);
  assert.equal((hooks.match(/supersedeStop\(\)/g) ?? []).length >= 6, true, "prompt, tool, post-tool, failure and both notifications");
  assert.match(hooks, /stopTimers\.arm\(/);
  const views = source("views/views.ts");
  assert.match(views, /new ClickGuard\(\)/);
  assert.match(views, /guard\.blocks\(performance\.now\(\)\)/);
  assert.match(views, /guard\.shown\(State\.pendingApproval\?\.requestId \?\? null, performance\.now\(\)\)/);
});
