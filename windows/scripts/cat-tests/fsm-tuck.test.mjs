import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// Tuck the island away: the Windows and Linux twin of tests/IslandTuckAwayTests.swift (the Mac). The rule is windows/src/island/tuckaway.ts; the compact island's one timer is
// IslandStateMachine's, run here on a clock these tests turn by hand (seconds, as the Mac's). The same cases, in the same order.

// The FSM calls window.setTimeout (milliseconds): give it one that the test turns by hand.
let clock = 10000; // seconds: the time the rules read
let nextId = 1;
const timers = new Map();
globalThis.window = {
  setTimeout: (fn, ms) => { const id = nextId++; timers.set(id, { fn, at: clock + ms / 1000 }); return id; },
  clearTimeout: (id) => { timers.delete(id); },
};
function advance(s) {
  const end = clock + s;
  for (;;) {
    const due = [...timers.entries()].filter(([, x]) => x.at <= end + 1e-9).sort((a, b) => a[1].at - b[1].at)[0];
    if (!due) break;
    clock = Math.max(clock, due[1].at);
    timers.delete(due[0]);
    due[1].fn();
  }
  clock = end;
}
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const { IslandStateMachine } = await import("../../src/island/fsm.ts");
const rule = await import("../../src/island/tuckaway.ts");

/** A compact island's state machine on the clock, with the setting and the last activity at the clock's now. */
function machine(choice) {
  timers.clear();
  const f = new IslandStateMachine();
  f.now = () => clock;
  f.tuckAway = choice;
  f.agentActivity();
  return f;
}
const armed = () => timers.size;

test("the stored value is cleaned: a missing or unknown one is never, the five choices are kept", () => {
  assert.equal(rule.cleanTuckChoice(undefined), "never");
  assert.equal(rule.cleanTuckChoice(null), "never");
  for (const raw of ["never", "1", "5", "15", "30"]) assert.equal(rule.cleanTuckChoice(raw), raw);
  for (const raw of ["", "7", "10", "Never", " 5", "5 ", "60", "hour", 5]) assert.equal(rule.cleanTuckChoice(raw), "never", String(raw));
  assert.deepEqual(rule.TUCK_CHOICES, ["never", "1", "5", "15", "30"]);
  assert.equal(rule.tuckMinutes("never"), null);
  assert.equal(rule.tuckMinutes("1"), 1);
  assert.equal(rule.tuckMinutes("30"), 30);
});

test("live: only a pill working, thinking, searching or waiting; an open session that is idle, or a finished or idle pill, is not", () => {
  assert.equal(rule.isLive(["idle", "idle"]), false);
  for (const s of ["working", "thinking", "searching", "approval", "question"]) assert.equal(rule.isLive(["idle", s]), true, s);
  for (const s of ["finished", "error", "ratelimit", "sleeping", "dizzy"]) assert.equal(rule.isLive([s]), false, s);
  assert.equal(rule.isLive([]), false, "no pill: an open session alone is not live");
});

test("a click on the island restarts the minute: folded after the click, it hides a minute after the click", () => {
  const f = machine("1");
  f.reveal();
  advance(50);
  f.userInteracted();
  assert.equal(armed(), 1, "one timer, re-armed by the click");
  advance(50);
  assert.equal(f.state, "petit", "at 100 s after the reveal, still up");
  advance(10);
  assert.equal(f.state, "hidden", "hidden 60 s after the click");
});

test("the delay: null while the island may not hide by itself, otherwise the seconds left, never negative", () => {
  assert.equal(rule.hideDelay("never", 0, 99999, false), null, "never");
  assert.equal(rule.hideDelay("5", 0, 0, true), null, "live");
  assert.equal(rule.hideDelay("5", 1000, 1000, false), 300);
  assert.equal(rule.hideDelay("5", 1000, 1120, false), 180);
  assert.equal(rule.hideDelay("5", 1000, 1300, false), 0);
  assert.equal(rule.hideDelay("1", 1000, 5000, false), 0);
});

test("the parity pin: the Swift rule's choices, live states and key are the same as these", () => {
  const swift = fs.readFileSync(new URL("../../../NotchBuddy/Sources/App/IslandTuckAway.swift", import.meta.url), "utf8").replace(/\/\/[^\n]*/g, "");
  assert.equal(swift.includes('static let defaultsKey = "island.tuckAway"'), true);
  assert.match(swift, /case never\s+case m1 = "1"\s+case m5 = "5"\s+case m15 = "15"\s+case m30 = "30"/);
  assert.match(swift, /static let liveStates: Set<String> = \["working", "thinking", "searching", "approval", "question"\]/);
  assert.deepEqual([...rule.LIVE_STATES].sort(), ["approval", "question", "searching", "thinking", "working"]);
  assert.doesNotMatch(swift, /openSessions/, "the live rule reads the pills' states only, on both sides");
});

test("never (the default): the compact island stays for an hour and arms no timer, however the pointer comes and goes", () => {
  const f = machine("never");
  f.reveal();
  advance(3600);
  assert.equal(f.state, "petit");
  assert.equal(armed(), 0);
  f.mouseEntered();
  f.mouseLeft();
  advance(3600);
  assert.equal(f.state, "petit");
  assert.equal(armed(), 0);
  assert.equal(new IslandStateMachine().tuckAway, "never", "the default is never");
});

test("1 min: hides exactly a minute after the last activity, one timer armed", () => {
  const f = machine("1");
  f.reveal();
  assert.equal(f.state, "petit");
  assert.equal(armed(), 1);
  advance(59);
  assert.equal(f.state, "petit", "59 s quiet: still up");
  advance(1);
  assert.equal(f.state, "hidden", "60 s quiet: hidden");
  assert.equal(armed(), 0);
});

test("an activity starts the minute again, and the one timer is re-armed, not doubled", () => {
  const f = machine("1");
  f.reveal();
  advance(50);
  f.agentActivity();
  assert.equal(f.state, "petit");
  assert.equal(armed(), 1);
  advance(50);
  assert.equal(f.state, "petit", "at 100 s after the reveal, still up");
  advance(10);
  assert.equal(f.state, "hidden", "hidden 60 s after the activity");
});

test("a wing fold (the pointer leaving) neither starts nor shortens the countdown", () => {
  const f = machine("5");
  f.reveal();
  advance(120);
  f.mouseLeft();
  assert.equal(armed(), 1, "one timer for what is left: 3 min");
  advance(179);
  assert.equal(f.state, "petit");
  advance(1);
  assert.equal(f.state, "hidden", "five minutes from the last activity");
});

test("the pointer on the island holds it, even past the time; leaving then hides it, since it is due", () => {
  const f = machine("1");
  f.reveal();
  f.mouseEntered();
  assert.equal(armed(), 0);
  advance(600);
  assert.equal(f.state, "petit", "ten minutes past the time, pointer on it: still up");
  f.mouseLeft();
  advance(0);
  assert.equal(f.state, "hidden", "the pointer leaves an island that is due: hidden at once");
});

test("a live agent holds it however long it is quiet; when nothing is live the time counts again", () => {
  const f = machine("1");
  f.reveal();
  f.setLive(true);
  assert.equal(armed(), 0, "a live agent: no timer");
  advance(600);
  assert.equal(f.state, "petit");
  f.setLive(false);
  advance(0);
  assert.equal(f.state, "hidden", "nothing live, the minute long past: hidden at once");
});

test("nothing live again with four minutes to go: one timer for those four minutes", () => {
  const f = machine("5");
  f.reveal();
  advance(60);
  f.setLive(true);
  advance(100);
  f.setLive(false);
  assert.equal(armed(), 1);
  advance(139);
  assert.equal(f.state, "petit");
  advance(1);
  assert.equal(f.state, "hidden");
});

test("changing the setting while the island is up re-arms it at once; back to never cancels it", () => {
  const on = machine("never");
  on.reveal();
  on.tuckAway = "1";
  assert.equal(armed(), 1, "a time turned on arms the timer for the island that is up");
  advance(60);
  assert.equal(on.state, "hidden", "a minute after the last activity, not after the change");
  const off = machine("1");
  off.reveal();
  off.tuckAway = "never";
  assert.equal(armed(), 0, "never cancels the timer");
  advance(600);
  assert.equal(off.state, "petit");
});

test("an activity while hidden arms nothing", () => {
  const f = machine("1");
  f.agentActivity();
  assert.equal(f.state, "hidden");
  assert.equal(armed(), 0);
});

test("twenty activities, live changes and leaves: still exactly one timer", () => {
  const f = machine("5");
  f.reveal();
  for (let i = 0; i < 20; i++) {
    advance(1);
    f.agentActivity();
    f.setLive(false);
    f.mouseLeft();
  }
  assert.equal(armed(), 1);
});

test("held by a pinned alert: a timer that fires while pinned does not hide the island and arms nothing; the release hides it at once", () => {
  const f = machine("1");
  f.reveal();
  assert.equal(armed(), 1);
  f.pinned = true;
  advance(600);
  assert.equal(f.state, "petit", "the minute ran out while pinned: still up");
  assert.equal(armed(), 0, "no timer is left armed");
  f.pinned = false;
  advance(0);
  assert.equal(f.state, "hidden", "the pin released: hidden at once");
});

test("a send ending during a drag keeps the island held: each hold has its own flag, and the last release re-arms the timer", () => {
  const f = machine("1");
  f.reveal();
  f.setShelfHold("drag", true);
  f.setShelfHold("send", true);
  advance(600);
  assert.equal(f.state, "petit", "due, held by the drag and the send: still up");
  f.setShelfHold("send", false);
  advance(0);
  assert.equal(f.state, "petit", "the send ended mid-drag: the drag still holds it");
  assert.equal(armed(), 0);
  f.setShelfHold("drag", false);
  advance(0);
  assert.equal(f.state, "hidden", "the drag ended too: hidden at once");
});

test("a click with a button other than the primary one does not restart the minute", () => {
  const f = machine("1");
  f.reveal();
  advance(50);
  f.userInteracted(false);
  advance(50);
  assert.equal(f.state, "hidden", "a right click at 50 s: the minute still runs from the reveal, hidden at 60 s");
});

test("never: a pin that ends arms nothing, and the island stays up", () => {
  const f = machine("never");
  f.reveal();
  f.pinned = true;
  f.pinned = false;
  assert.equal(armed(), 0, "the release arms no timer");
  advance(3600);
  assert.equal(f.state, "petit", "an hour after the pin ended, still up");
  assert.equal(armed(), 0);
});

test("an open menu holds the compact island: no timer while it is up, and the timer starts when it closes", () => {
  const f = machine("1");
  f.mouseEntered();
  f.menuHold(true, true);
  f.mouseLeft();
  assert.equal(armed(), 0, "no timer while the menu is up");
  f.menuHold(false, false);
  assert.equal(armed(), 1, "closing the menu with the pointer outside arms the timer");
});
