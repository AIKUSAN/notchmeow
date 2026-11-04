import test from "node:test";
import assert from "node:assert/strict";
import { dropZone, planDrop, pointerX } from "../../src/shelf/dropflow.ts";

// Which half a drop landed in and what it does (G1). The half itself is the contract's zoneAt (shelf-rules.test.mjs).
const win = { cursorPoll: true, polledX: 100, position: null, scale: 1.5, islandX: 40 };

test("with a global cursor (Windows) the polled x is the pointer, whatever position the event carried", () => {
  assert.equal(pointerX(win), 100);
  assert.equal(pointerX({ ...win, position: { x: 900, y: 10 } }), 100);
});

test("without one (Linux) the event's position is the pointer: physical px to CSS px, then from the island's left edge", () => {
  const lin = { ...win, cursorPoll: false, position: { x: 780, y: 10 } };
  assert.equal(pointerX(lin), 780 / 1.5 - 40);
  assert.equal(pointerX({ ...lin, position: null }), 100, "no position: the last polled x");
  assert.equal(pointerX({ ...lin, scale: 0 }), 100, "a scale that cannot divide is not used");
});

test("dropZone is the contract's rule on that pointer: the centre line is Ask, the right half Shelf, outside is null", () => {
  assert.equal(dropZone({ ...win, polledX: 320 }, 640), "ask");
  assert.equal(dropZone({ ...win, polledX: 320.5 }, 640), "shelf");
  assert.equal(dropZone({ ...win, polledX: 639 }, 640), "shelf");
  assert.equal(dropZone({ ...win, polledX: 100 }, 640), "ask");
  assert.equal(dropZone({ ...win, polledX: -2 }, 640), null);
  assert.equal(dropZone({ ...win, polledX: 641 }, 640), null);
  assert.equal(dropZone({ ...win, polledX: NaN }, 640), null);
  assert.equal(dropZone({ ...win, cursorPoll: false, position: { x: (40 + 400) * 1.5, y: 0 } }, 640), "shelf");
});

test("a drop on Ask takes the first file only; on Shelf all of them in order; outside both it is Ask's; no files is nothing", () => {
  const paths = ["/a.txt", "/b.txt", "/c.txt"];
  assert.deepEqual(planDrop("ask", paths), { kind: "ask", path: "/a.txt" });
  assert.deepEqual(planDrop("shelf", paths), { kind: "shelf", paths });
  assert.deepEqual(planDrop(null, paths), { kind: "ask", path: "/a.txt" });
  assert.deepEqual(planDrop("shelf", []), { kind: "none" });
  assert.deepEqual(planDrop("ask", undefined), { kind: "none" });
  const copy = planDrop("shelf", paths);
  copy.paths.push("/x");
  assert.equal(paths.length, 3, "the plan holds a copy");
});
