import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { SLEEP_AFTER_MS, WAKE_EVENTS, sleepDelay, wakes } from "../../src/cat/base.ts";
import { State } from "../../src/core/state.ts";
import { SleepClock } from "../../src/island/sleep.ts";
import { load } from "./util.mjs";

const fx = load("sequence-cases.json").sleep;
const MIN = 60_000;
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");

/** A clock and a timer queue the test turns by hand, and a cat that records what happens to it. */
function world() {
  const w = { t: 0, state: "idle", blocked: false, timers: new Map(), id: 1, sets: 0, clears: 0, falls: 0, wakes: 0 };
  const env = {
    now: () => w.t, state: () => w.state, blocked: () => w.blocked,
    set: (fn, ms) => { const id = w.id++; w.sets++; w.timers.set(id, { fn, at: w.t + ms }); return id; },
    clear: (id) => { w.clears++; w.timers.delete(id); },
    fall: () => { w.falls++; }, wake: () => { w.wakes++; },
  };
  w.advance = (ms) => {
    const end = w.t + ms;
    for (;;) {
      const due = [...w.timers.entries()].filter(([, x]) => x.at <= end).sort((a, b) => a[1].at - b[1].at)[0];
      if (!due) break;
      w.t = due[1].at; w.timers.delete(due[0]); due[1].fn();
    }
    w.t = end;
  };
  return { w, clock: new SleepClock(env) };
}

test("the rule is the contract's: ten minutes, only an idle cat, and a hook, a hover or a click wakes it", () => {
  assert.equal(SLEEP_AFTER_MS, fx.afterMs);
  assert.equal(SLEEP_AFTER_MS, 10 * MIN);
  assert.ok(fx.cases.length >= 50);
  for (const c of fx.cases) assert.equal(sleepDelay(c.state, c.quietMs), c.delayMs, `${c.state} after ${c.quietMs} ms`);
  for (const w of fx.wake) assert.equal(wakes(w.kind), w.wakes, JSON.stringify(w.kind));
  assert.deepEqual([...WAKE_EVENTS], ["hook", "hover", "click"]);
  for (const odd of [undefined, null, 7, {}, ["hook"], "Hook"]) assert.equal(wakes(odd), false, String(odd));
  for (const bad of [NaN, Infinity, -Infinity, -5000]) assert.equal(sleepDelay("idle", bad), SLEEP_AFTER_MS, `a quiet time of ${bad} counts as 0`);
});

test("an idle cat falls asleep after exactly ten minutes without an event, once, and the timer is not re-armed", () => {
  const { w } = world();
  assert.equal(w.timers.size, 1, "armed at start-up");
  w.advance(10 * MIN - 1);
  assert.equal(w.falls, 0);
  w.advance(1);
  assert.equal(w.falls, 1);
  assert.equal(w.timers.size, 0, "nothing left to fire: no polling");
  w.advance(60 * MIN);
  assert.equal(w.falls, 1);
});

test("every event starts the ten minutes again, with one timer at a time and no polling", () => {
  const { w, clock } = world();
  w.advance(5 * MIN);
  clock.event("hook");
  w.advance(10 * MIN - 1);
  assert.equal(w.falls, 0, "the first event moved it to 15 minutes");
  w.advance(1);
  assert.equal(w.falls, 1);
  const busy = world();
  for (let i = 0; i < 100; i++) { busy.w.advance(1000); busy.clock.event(i % 2 ? "hover" : "hook"); }
  assert.equal(busy.w.timers.size, 1, "one timer, however many events");
  assert.equal(busy.w.sets, 101, "one set at start-up and one per event, nothing in between");
  assert.equal(busy.w.falls, 0);
  assert.doesNotMatch(source("island/sleep.ts"), /setInterval/);
});

test("it never sleeps through an approval or a question, nor while the cat is not idle, and the next event starts it again", () => {
  const a = world();
  a.w.state = "approval";
  a.w.advance(10 * MIN);
  assert.deepEqual([a.w.falls, a.w.timers.size], [0, 0], "an approval is not slept through");
  for (const state of ["question", "working", "thinking", "searching", "finished", "error", "ratelimit", "dizzy"]) {
    const x = world(); x.w.state = state; x.w.advance(10 * MIN);
    assert.equal(x.w.falls, 0, state);
  }
  const b = world();
  b.w.blocked = true;
  b.w.advance(10 * MIN);
  assert.equal(b.w.falls, 0, "a card is waiting for an answer");
  b.w.blocked = false; b.w.state = "idle";
  b.clock.event("hook");
  b.w.advance(10 * MIN);
  assert.equal(b.w.falls, 1, "after the next event it works as ever");
});

test("a pill that finished goes back to idle on its own: the ten minutes are counted from the event, not from then", () => {
  const { w, clock } = world();
  w.state = "finished";
  clock.event("hook");
  w.advance(5200);
  w.state = "idle";
  w.advance(10 * MIN - 5200);
  assert.equal(w.falls, 1);
});

test("a hook, a hover and a click wake the cat and restart the clock; a key, a scroll or a drag change nothing", () => {
  const { w, clock } = world();
  for (const kind of WAKE_EVENTS) { clock.event(kind); assert.equal(w.wakes, WAKE_EVENTS.indexOf(kind) + 1, kind); }
  const sets = w.sets;
  for (const kind of ["key", "scroll", "drag", "", undefined, null, 7]) clock.event(kind);
  assert.deepEqual([w.wakes, w.sets], [3, sets], "ignored events do not wake it and do not touch the timer");
});

test("a timer that fires early waits for the rest, and a clock that steps back is not a reason to sleep", () => {
  const { w } = world();
  const fire = (x) => { const [[id, t]] = [...x.timers.entries()]; x.timers.delete(id); t.fn(); };
  w.t = 10 * MIN - 2;
  fire(w);
  assert.equal(w.falls, 0);
  assert.equal(w.timers.size, 1, "two milliseconds to go: armed again for them");
  assert.equal([...w.timers.values()][0].at, w.t + 2);
  const back = world();
  back.w.t = -5000;
  fire(back.w);
  assert.equal(back.w.falls, 0);
  assert.equal([...back.w.timers.values()][0].at, back.w.t + 10 * MIN, "the full ten minutes again");
});

test("State: an idle cat shows as sleeping while asleep, nothing else does, and falling asleep and waking notify only when they change something", () => {
  State.loadIntegrationTasks();
  const seen = []; const off = State.subscribe(() => seen.push(State.effectiveState));
  try {
    assert.equal(State.asleep, false);
    assert.equal(State.effectiveState, "idle");
    State.fallAsleep(); State.fallAsleep();
    assert.equal(State.effectiveState, "sleeping");
    assert.equal(seen.length, 1, "the second call changed nothing");
    assert.deepEqual(["idle", "working", "thinking", "searching", "approval", "question", "error", "finished", "ratelimit", "dizzy"].map((s) => State.shownState(s)),
      ["sleeping", "working", "thinking", "searching", "approval", "question", "error", "finished", "ratelimit", "dizzy"]);
    State.updateTask("integration_claude", "approval");
    assert.equal(State.effectiveState, "approval", "an approval is never overridden");
    State.updateTask("integration_claude", "idle");
    State.stateOverride = "dizzy";
    assert.equal(State.effectiveState, "dizzy", "a poked cat is dizzy, asleep or not");
    State.stateOverride = null;
    State.wake(); State.wake();
    assert.equal(State.effectiveState, "idle");
    assert.deepEqual(seen, ["sleeping", "approval", "sleeping", "idle"], "one notification per change: falling asleep, the approval, back to idle (asleep), waking; the second wake changed nothing");
  } finally { off(); State.asleep = false; State.stateOverride = null; }
});

test("the wiring: the hook handlers, the island's hover and click, and the mini cats", () => {
  const island = source("island/island.ts"), hooks = source("island/hooks.ts"), mini = source("cat/minibots.ts");
  assert.match(island, /private sleep = new SleepClock\(\{/);
  assert.match(island, /fall: \(\) => State\.fallAsleep\(\),/);
  assert.match(island, /wake: \(\) => State\.wake\(\),/);
  assert.match(island, /noteActivity\(kind: "hook" \| "hover" \| "click"\) \{\s*this\.sleep\.event\(kind\);/);
  assert.match(island, /if \(inIsland && !this\.wasInIsland\) \{\s*this\.sleep\.event\("hover"\);/);
  assert.match(island, /addEventListener\("mousedown", \(e\) => \{\s*Sound\.resume\(\);\s*this\.sleep\.event\("click"\);/);
  assert.match(hooks, /function handleHook\(island: Island, payload: HookPayload, stepBack\?: FocusMark\) \{\s*island\.noteActivity\("hook"\);/);
  assert.equal([...mini.matchAll(/State\.shownState\(task\.state\)/g)].length, 2, "when a mini cat is made, and each time the tasks sync");
});
