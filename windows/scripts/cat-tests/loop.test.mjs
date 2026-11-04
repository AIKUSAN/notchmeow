import test from "node:test";
import assert from "node:assert/strict";
import { VisibleLoop } from "../../src/cat/loop.ts";

/** A frame clock the test turns by hand, and a page that can be shown and hidden. */
function page() {
  const p = { visible: true, pending: new Map(), next: 1, cancelled: 0 };
  p.env = {
    raf: (cb) => { const id = p.next++; p.pending.set(id, cb); return id; },
    caf: (id) => { if (p.pending.delete(id)) p.cancelled++; },
    visible: () => p.visible,
  };
  p.frame = (ms) => { const cbs = [...p.pending.values()]; p.pending.clear(); for (const cb of cbs) cb(ms); };
  return p;
}

test("nothing is scheduled until the page can be seen, and a hidden page schedules nothing", () => {
  const p = page(), dts = [];
  const loop = new VisibleLoop((dt) => dts.push(dt), p.env);
  assert.equal(loop.running, false);
  p.visible = false;
  loop.sync();
  assert.equal(p.pending.size, 0);
  assert.equal(loop.running, false);
  p.visible = true;
  loop.sync();
  assert.equal(p.pending.size, 1);
  assert.equal(loop.running, true);
  loop.sync(); loop.sync();
  assert.equal(p.pending.size, 1, "syncing again does not schedule a second frame");
});

test("a frame draws, then asks for the next; the first dt is 0 and a long gap is held to 0.05 s", () => {
  const p = page(), dts = [];
  const loop = new VisibleLoop((dt) => dts.push(dt), p.env);
  loop.sync();
  p.frame(1000); p.frame(1016); p.frame(5000); p.frame(5010);
  assert.deepEqual(dts.map((d) => Math.round(d * 1000) / 1000), [0, 0.016, 0.05, 0.01]);
  assert.equal(p.pending.size, 1);
});

test("a clock that steps back gives a dt of 0, never a negative or a NaN", () => {
  const p = page(), dts = [];
  new VisibleLoop((dt) => dts.push(dt), p.env).sync();
  p.frame(1000); p.frame(900); p.frame(NaN);
  assert.ok(dts.every((d) => Number.isFinite(d) && d >= 0), String(dts));
});

test("hiding the page stops the loop at once: the pending frame is cancelled, and a frame already due draws nothing", () => {
  const p = page(); let drawn = 0;
  const loop = new VisibleLoop(() => { drawn++; }, p.env);
  loop.sync();
  p.frame(1000);
  assert.equal(drawn, 1);
  p.visible = false;
  loop.sync();
  assert.equal(p.pending.size, 0);
  assert.equal(p.cancelled, 1);
  assert.equal(loop.running, false);
  // The page was hidden between two syncs (no event yet): the due frame notices and stops by itself.
  p.visible = true; loop.sync();
  p.visible = false;
  p.frame(2000);
  assert.equal(drawn, 1, "no drawing while hidden");
  assert.equal(p.pending.size, 0, "and no next frame");
  assert.equal(loop.running, false);
});

test("showing the page again restarts it, with a first dt of 0 rather than the whole time it was away", () => {
  const p = page(), dts = [];
  const loop = new VisibleLoop((dt) => dts.push(dt), p.env);
  loop.sync(); p.frame(1000);
  p.visible = false; loop.sync();
  p.visible = true; loop.sync();
  p.frame(600000);
  assert.deepEqual(dts, [0, 0]);
});
