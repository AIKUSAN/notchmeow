import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

// The FSM calls window.setTimeout: give it one that the test turns by hand.
let now = 0, nextId = 1;
const timers = new Map();
globalThis.window = {
  setTimeout: (fn, ms) => { const id = nextId++; timers.set(id, { fn, at: now + ms }); return id; },
  clearTimeout: (id) => { timers.delete(id); },
};
function seconds(s) {
  const end = now + s * 1000;
  for (;;) {
    const due = [...timers.entries()].filter(([, x]) => x.at <= end).sort((a, b) => a[1].at - b[1].at)[0];
    if (!due) break;
    now = due[1].at; timers.delete(due[0]); due[1].fn();
  }
  now = end;
}
const { IslandStateMachine } = await import("../../src/island/fsm.ts");
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
function machine() { timers.clear(); return new IslandStateMachine(); }

// The cases of tests/IslandHoverTests.swift (the Mac), in the same order, with the 150 ms dwell.
function entered(fsm) { fsm.mouseEntered(); seconds(0.15); }   // the pointer stays over the island for the dwell: it opens

test("open on hover off: hovering only peeks and arms no timer", () => {
  const fsm = machine();
  fsm.mouseEntered();
  seconds(5);
  assert.equal(fsm.state, "petit");
  assert.equal(fsm.openedByHover, false);
});

test("the dwell: 149 ms over the island does not open it, 150 ms does", () => {
  const fsm = machine();
  assert.equal(fsm.hoverDwell, 0.15);
  fsm.openOnHover = true;
  fsm.mouseEntered();
  assert.equal(fsm.state, "petit", "the usual peek is not delayed");
  seconds(0.149);
  assert.equal(fsm.state, "petit");
  assert.equal(fsm.openedByHover, false);
  seconds(0.001);
  assert.equal(fsm.state, "home");
  assert.equal(fsm.openedByHover, true);
  assert.equal(timers.size, 0, "no timer is left armed once it has opened");
});

test("leaving at 100 ms cancels the open; coming back starts a new dwell", () => {
  const fsm = machine();
  fsm.openOnHover = true;
  fsm.mouseEntered();
  seconds(0.1);
  fsm.mouseLeft();
  assert.ok([...timers.values()].every((t) => t.at - now > 1000), "no dwell timer is left (at most the tuck-away timer)");
  seconds(0.5);
  assert.equal(fsm.state, "petit");
  assert.equal(fsm.openedByHover, false);
  fsm.mouseEntered();
  seconds(0.149);
  assert.equal(fsm.state, "petit");
  seconds(0.001);
  assert.equal(fsm.state, "home");
});

test("open on hover: opened by the dwell with the pointer still over it, no fold ever starts", () => {
  const fsm = machine();
  fsm.openOnHover = true;
  fsm.homeToPetitDelay = 0.05;
  fsm.hoverCloseDelay = 0.05;
  entered(fsm);
  assert.equal(fsm.state, "home");
  seconds(120);
  assert.equal(fsm.state, "home", "no mouseLeft yet: nothing folds it, in this poll or any later one");
  assert.equal(fsm.openedByHover, true);
});

test("open on hover: a native menu holds the dwell too", () => {
  const fsm = machine();
  fsm.openOnHover = true;
  fsm.menuHold(true, true);
  fsm.mouseEntered();
  seconds(1);
  assert.equal(fsm.state, "petit", "the menu is up: hover does not open the island under it");
});

test("open on hover: leaving folds after the short grace period", () => {
  const fsm = machine();
  fsm.openOnHover = true;
  entered(fsm);
  assert.equal(fsm.state, "home");
  assert.equal(fsm.openedByHover, true);
  fsm.mouseLeft();
  seconds(0.5);
  assert.equal(fsm.state, "home");
  seconds(0.1);
  assert.equal(fsm.state, "petit");
  assert.equal(fsm.openedByHover, false);
  entered(fsm);                   // from the compact island it opens again
  assert.equal(fsm.state, "home");
});

test("open on hover: coming back before the grace period keeps it open", () => {
  const fsm = machine();
  fsm.openOnHover = true;
  entered(fsm);
  fsm.mouseLeft();
  seconds(0.3);
  fsm.mouseEntered();
  seconds(5);
  assert.equal(fsm.state, "home");
});

test("open on hover: a click inside makes it an ordinary open island", () => {
  const fsm = machine();
  fsm.openOnHover = true;
  fsm.homeToPetitDelay = 3;
  entered(fsm);
  fsm.mouseLeft();
  fsm.userInteracted();          // the short countdown becomes the normal one
  seconds(1);
  assert.equal(fsm.state, "home");
  seconds(2);
  assert.equal(fsm.state, "petit");
});

test("open on hover: an alert that pins the island is never opened or folded by hover, and one that arrives during the dwell wins", () => {
  const fsm = machine();
  fsm.openOnHover = true;
  fsm.pinned = true;
  fsm.mouseEntered();
  seconds(1);
  assert.equal(fsm.state, "petit", "pinned: no dwell is armed");
  assert.equal(fsm.openedByHover, false);
  fsm.forceHome();
  fsm.mouseLeft();
  seconds(5);
  assert.equal(fsm.state, "home");
  const other = machine();
  other.openOnHover = true;
  other.mouseEntered();
  other.forceHome();              // an alert during the dwell
  seconds(0.2);
  assert.equal(other.openedByHover, false);
});

test("open on hover: an island opened by an alert keeps the normal delay", () => {
  const fsm = machine();
  fsm.openOnHover = true;
  fsm.homeToPetitDelay = 3;
  fsm.forceHome();
  fsm.mouseEntered();
  assert.equal(timers.size, 0, "an island that is already open arms no dwell");
  fsm.mouseLeft();
  seconds(1);
  assert.equal(fsm.state, "home");
  seconds(2);
  assert.equal(fsm.state, "petit");
});

test("the wiring: the island feeds the setting to the machine, keeps the shipped poll order, and a click is an interaction", () => {
  const isl = source("island/island.ts");
  assert.equal((isl.match(/this\.fsm\.openOnHover = State\.settings\.openOnHover;/g) ?? []).length, 2, "at start and in applySettings");
  assert.match(isl, /this\.fsm\.userInteracted\(e\.button === 0\);/);
  // The poll's order is the shipped one (decided in review: the dwell's open is a timer, so nothing needs the pointer recorded earlier, and with the switch off nothing may change):
  // the state machine hears of the enter and the leave first, the pointer is recorded after both, and the wake strip does not touch it.
  assert.match(isl, /if \(inIsland && !this\.wasInIsland\) \{\s*this\.sleep\.event\("hover"\);/);
  assert.match(isl, /if \(!inIsland && this\.wasInIsland\) \{\s*this\.fsm\.mouseLeft\(\);[\s\S]*?\n    this\.wasInIsland = inIsland;\n/);
  assert.doesNotMatch(isl, /const wasIn = this\.wasInIsland;/);
  // The wake strip records the pointer only with the switch on (Linux has no cursor poll: the dwell's open would read the pointer as outside and fold over it).
  // ... and only for a pointer inside the poll's hit rect (the strip is wider than it).
  assert.match(isl, /if \(this\.fsm\.openOnHover && this\.hitRectContains\(e\.clientX, e\.clientY\)\) \{[^}]*this\.wasInIsland = true;[^}]*\}\n\s+this\.fsm\.mouseEntered\(\);/);
});
