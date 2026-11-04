import test from "node:test";
import assert from "node:assert/strict";
import { desktopFlightAt } from "../../src/cat/desktop.ts";
import { DesktopFlight } from "../../src/cat/desktopflight.ts";
import { finite, near } from "./util.mjs";

// The flight's clock (sub-project H): the path is the contract's `desktopFlightAt`; this keeps the time, turns the flight round and moves its ends.

test("a flight keeps its own clock: it ends in 600 ms at the target, and the same flight swapped retraces itself", () => {
  const a = { x: 480, y: 16 }, b = { x: 900, y: 500 };
  const f = new DesktopFlight(a, b, 1000, "out");
  assert.deepEqual([f.progress(1000), f.progress(1300), f.progress(1600), f.progress(9999), f.progress(500)], [0, 0.5, 1, 1, 0]);
  near(f.at(1000).x, a.x); near(f.at(1600).y, b.y);
  assert.equal(f.at(1599).done, false);
  assert.equal(f.at(1600).done, true);
  for (const t of [0, 0.25, 0.5, 0.9]) near(f.at(1000 + 600 * t).x, desktopFlightAt(a, b, t).x);
  assert.equal(f.direction, "out");
});

test("a flight that turns around carries on from 1 - t and is exactly where it was at the turn, then ends at the notch (a send-home or an alert that clears)", () => {
  const notch = { x: 480, y: 16 }, desk = { x: 900, y: 500 };
  const f = new DesktopFlight(notch, desk, 0, "out");
  const before = f.at(240);
  f.turn(240);
  const after = f.at(240);
  near(after.x, before.x); near(after.y, before.y);
  assert.equal(f.direction, "in");
  assert.equal(f.at(240 + 239).done, false);
  assert.equal(f.at(240 + 240).done, true, "back at the notch after the same time it had flown");
  near(f.at(480).x, notch.x); near(f.at(480).y, notch.y);
  f.turn(480);
  assert.equal(f.direction, "out");
  near(f.progress(480), 0, 1e-12);
  near(f.at(480).x, notch.x);
});

test("the notch end of a flight follows the notch spot, whichever way it flies, and the desktop end follows the desktop spot", () => {
  const f = new DesktopFlight({ x: 0, y: 0 }, { x: 100, y: 100 }, 0, "out");
  f.setNotch({ x: 10, y: 10 });
  near(f.at(0).x, 10);
  f.setDesktop({ x: 200, y: 200 });
  near(f.at(600).x, 200);
  f.turn(600);
  f.setNotch({ x: 30, y: 30 });
  near(f.at(600 + 600).x, 30, 1e-9);
  f.setNotch({ x: NaN, y: 0 });
  near(f.at(600 + 600).x, 30, 1e-9);
  assert.equal(new DesktopFlight({ x: NaN, y: 1 }, null, NaN, "in", -5).at(0).done, false);
  finite(new DesktopFlight(null, undefined, Infinity, "out", NaN).at(NaN));
});
