import test from "node:test";
import assert from "node:assert/strict";

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
function machine() { timers.clear(); const f = new IslandStateMachine(); f.openOnHover = true; return f; }

// The wing cases of tests/IslandHoverTests.swift (the Mac): the pointer on a wing is a hover-only hold.
test("the pointer on a wing arms no dwell, with Open on hover on", () => {
  const fsm = machine();
  fsm.pointerOnWing = true;
  fsm.mouseEntered();
  seconds(1);
  assert.equal(fsm.state, "petit", "the usual peek still happens");
  assert.equal(fsm.openedByHover, false);
});

test("a wing reached while the dwell runs cancels the open", () => {
  const fsm = machine();
  fsm.mouseEntered();
  seconds(0.1);
  fsm.pointerOnWing = true;
  seconds(0.1);
  assert.equal(fsm.state, "petit");
  assert.equal(fsm.openedByHover, false);
});

test("coming off a wing into the middle arms the dwell again, and the island opens 150 ms later", () => {
  const fsm = machine();
  fsm.pointerOnWing = true;
  fsm.mouseEntered();
  seconds(0.5);
  fsm.pointerOnWing = false;
  fsm.hoverResume();
  seconds(0.149);
  assert.equal(fsm.state, "petit");
  seconds(0.001);
  assert.equal(fsm.state, "home");
  assert.equal(fsm.openedByHover, true);
});

test("hoverResume does nothing with the switch off, a pin, a menu, a wing under the pointer, or an island that is already open", () => {
  for (const edit of [(f) => { f.openOnHover = false; }, (f) => { f.pinned = true; }, (f) => { f.menuOpen = true; }, (f) => { f.pointerOnWing = true; }]) {
    const fsm = machine();
    fsm.pointerOnWing = true;           // no dwell is armed on entry
    fsm.mouseEntered();
    fsm.pointerOnWing = false;
    edit(fsm);
    fsm.hoverResume();
    seconds(0.2);
    assert.equal(fsm.state, "petit");
  }
  const open = machine();
  open.forceHome();
  open.hoverResume();
  seconds(0.2);
  assert.equal(open.openedByHover, false, "an open island has nothing to resume");
});

test("with the switch off the pointer on a wing changes nothing", () => {
  const fsm = machine();
  fsm.openOnHover = false;
  fsm.pointerOnWing = true;
  fsm.mouseEntered();
  seconds(5);
  assert.equal(fsm.state, "petit");
});
