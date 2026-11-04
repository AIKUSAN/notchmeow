import test from "node:test";
import assert from "node:assert/strict";
import * as core from "../../src/projects/core.ts";
import { nextDelay, ProjectsTick, PeekDwell } from "../../src/projects/clock.ts";

// The one tick (ProjectsClock.nextDelay, ProjectsModel's arm and rearm) and the peek's dwell, over an injected one-shot timer and clock.

const P = core;
const T = 1_000_000;

/** A one-shot timer that never runs on its own: `fire()` runs the first one set. */
function fake() {
  let next = 1;
  const live = new Map();
  return {
    live,
    set(fn, ms) { const id = next++; live.set(id, { fn, ms }); return id; },
    clear(id) { live.delete(id); },
    fire() { const [id, e] = live.entries().next().value; live.delete(id); e.fn(); },
  };
}

test("nextDelay: 60 s with nothing due, the nearest later boundary otherwise, never at or before now, never below 50 ms", () => {
  const reg = (events) => events.reduce((r, [at, p]) => P.registryApply(r, P.projectEventFrom(p, at)), P.emptyRegistry("C:/Users/dev"));
  assert.equal(nextDelay(P.emptyRegistry(""), T), 60_000);
  const stop = reg([[T, { hook_event_name: "UserPromptSubmit", session_id: "s", cwd: "C:/dev/a" }], [T + 1000, { hook_event_name: "Stop", session_id: "s" }]]);
  assert.equal(nextDelay(stop, T + 1000), 5200, "finished ends 5.2 s after the stop");
  assert.equal(nextDelay(stop, T + 6200), 60_000, "a boundary at exactly now has passed");
  assert.equal(nextDelay(stop, T + 6190), 50, "the floor");
  const ask = reg([[T, { hook_event_name: "PermissionRequest", session_id: "s", cwd: "C:/dev/a", tool_name: "Bash" }]]);
  assert.equal(nextDelay(ask, T + 100_000), 20_000, "a card's approval ends at 120 s");
});

test("ProjectsTick: one one-shot while open, re-armed only for an earlier boundary, cleared once folded", () => {
  const t = fake(); let now = 0, delay = 60_000, fired = 0;
  const k = new ProjectsTick(t, () => now, () => delay, () => fired++);
  k.sync(false); assert.equal(t.live.size, 0);
  k.sync(true); k.sync(true); assert.equal(t.live.size, 1); assert.equal([...t.live.values()][0].ms, 60_000);
  now = 1000; delay = 60_000; k.sync(true); assert.equal([...t.live.values()][0].ms, 60_000, "a later boundary never pushes it back");
  delay = 5200; k.sync(true); assert.deepEqual([t.live.size, [...t.live.values()][0].ms], [1, 5200], "an earlier one replaces it");
  t.fire(); assert.deepEqual([fired, k.armed], [1, false]);
  k.sync(true); k.sync(false); assert.equal(t.live.size, 0);
});

test("PeekDwell: shows after PEEK_DWELL_MS on the same pill; leaving clears and hides; a new pill replaces the pending one", () => {
  const t = fake(); const seen = []; const d = new PeekDwell(t, (id) => seen.push(`show ${id}`), () => seen.push("hide"));
  d.enter("p1"); assert.equal([...t.live.values()][0].ms, 400);
  d.enter("p2"); assert.equal(t.live.size, 1);
  t.fire(); assert.deepEqual([seen, d.shown], [["show p2"], "p2"]);
  d.leave(); assert.deepEqual([seen.at(-1), d.shown, t.live.size], ["hide", null, 0]);
});

test("nextDelay: a working session's turn to idle at QUIET_IDLE_MS (10 min), a question card at 130 s, an in-app wait at 10 min, each as the nearest boundary", () => {
  const reg = (events) => events.reduce((r, [at, p]) => P.registryApply(r, P.projectEventFrom(p, at)), P.emptyRegistry("C:/Users/dev"));
  const work = reg([[T, { hook_event_name: "UserPromptSubmit", session_id: "s", cwd: "C:/dev/a" }]]);
  assert.equal(nextDelay(work, T + P.QUIET_IDLE_MS - 5000), 5000, "the quiet ends 10 min after the last event");
  assert.equal(nextDelay(work, T + P.QUIET_IDLE_MS + 1), 60_000, "after it has passed, the next boundary is the minute");
  const q = reg([[T, { hook_event_name: "PreToolUse", session_id: "s", cwd: "C:/dev/a", tool_name: "AskUserQuestion", tool_input: {} }]]);
  assert.equal(nextDelay(q, T + 130_000 - 5000), 5000, "a question on a card ends at 130 s");
  const app = reg([[T, { hook_event_name: "PermissionRequest", session_id: "s", cwd: "C:/dev/a", nm_agent: "claude-desktop", tool_name: "Bash" }]]);
  assert.equal(nextDelay(app, T + P.APP_WAIT_MS - 5000), 5000, "a wait in the Claude App ends at 10 min");
});

test("PeekDwell: leaving before the dwell ends never shows and clears the timer; re-entering the pending pill does not restart the dwell", () => {
  const t = fake(); const seen = []; const d = new PeekDwell(t, (id) => seen.push(`show ${id}`), () => seen.push("hide"));
  d.enter("p1"); d.leave();
  assert.deepEqual([seen, d.shown, t.live.size], [[], null, 0], "a leave before the dwell shows nothing and leaves no timer");
  d.enter("p2");
  const [id, before] = [...t.live.entries()][0];
  d.enter("p2");
  assert.deepEqual([...t.live.entries()], [[id, before]], "the same pending id keeps its timer, so the dwell is not restarted");
  t.fire();
  assert.deepEqual(seen, ["show p2"]);
});
