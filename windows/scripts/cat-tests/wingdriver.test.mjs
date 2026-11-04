import test from "node:test";
import assert from "node:assert/strict";
import { WingDriver } from "../../src/island/wingdriver.ts";

// A clock and a timer the test turns by hand.
function rig({ button = () => false } = {}) {
  let t = 0, nextId = 1;
  const timers = new Map();
  const changes = [];
  const env = { now: () => t, set: (fn, ms) => { const id = nextId++; timers.set(id, { fn, at: t * 1000 + ms }); return id; }, clear: (id) => { timers.delete(id); } };
  const driver = new WingDriver(env, () => button(), (now, before) => changes.push([before.faded, now.faded, now.passThrough]));
  const advance = (s) => {
    const end = t + s;
    for (;;) {
      const due = [...timers.entries()].filter(([, x]) => x.at <= end * 1000).sort((a, b) => a[1].at - b[1].at)[0];
      if (!due) break;
      t = due[1].at / 1000; timers.delete(due[0]); due[1].fn();
    }
    t = end;
  };
  return { driver, advance, timers, changes, at: () => t };
}

test("the right wing folds at once and arms nothing while the pointer stays", () => {
  const r = rig();
  assert.deepEqual(r.driver.feed("right", true), { faded: true, passThrough: true });
  assert.equal(r.timers.size, 0, "no wake-up is needed while the pointer rests on a folded island");
  assert.deepEqual(r.changes, [[false, true, true]]);
});

test("the left wing folds by itself after the 0.4 s dwell, with one timer and no cursor event", () => {
  const r = rig();
  assert.deepEqual(r.driver.feed("left", true), { faded: false, passThrough: false });
  assert.equal(r.timers.size, 1, "one one-shot wake-up for the dwell");
  r.advance(0.39);
  assert.equal(r.driver.state.faded, false);
  r.advance(0.02);
  assert.deepEqual(r.driver.state, { faded: true, passThrough: true });
  assert.equal(r.timers.size, 0, "folded with the pointer on the wing: nothing pending");
});

test("it comes back by itself 1 s after the pointer has left, and then nothing is pending", () => {
  const r = rig();
  r.driver.feed("right", true);
  r.advance(3);
  r.driver.feed(null, true);
  assert.equal(r.timers.size, 1);
  r.advance(0.99);
  assert.equal(r.driver.state.faded, true);
  r.advance(0.02);
  assert.deepEqual(r.driver.state, { faded: false, passThrough: false });
  assert.equal(r.timers.size, 0);
  assert.equal(r.driver.pending, false);
});

test("an alert cancels it at once and clears the wake-up; leaving the left wing cancels the dwell", () => {
  const r = rig();
  r.driver.feed("left", true);
  r.driver.feed(null, true);
  assert.equal(r.timers.size, 0, "the dwell was cancelled, so no wake-up is left");
  r.driver.feed("right", true);
  r.driver.feed("right", false);
  assert.deepEqual(r.driver.state, { faded: false, passThrough: false });
  assert.equal(r.timers.size, 0);
});

test("a button pressed during the dwell cancels it when the page pokes the driver", () => {
  let down = false;
  const r = rig({ button: () => down });
  r.driver.feed("left", true);
  r.advance(0.2);
  down = true;
  r.driver.poke();
  assert.equal(r.timers.size, 0, "a press ends the dwell; nothing is pending until the button is up");
  r.advance(1);
  assert.equal(r.driver.state.faded, false);
  down = false;
  r.driver.poke();
  r.advance(0.41);
  assert.equal(r.driver.state.faded, true, "released: the dwell starts over and folds 0.4 s later");
});
