import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { CLICK_SLOP, ClickTracker, OutsideClick, shouldFold } from "../../src/island/outsideclick.ts";

// The cases of tests/IslandOutsideClickTests.swift (the Mac), in the same order.
const open = { expanded: true, pinned: false, held: false, typing: false, pointerInIsland: false, busy: false };
const withOnly = (edit) => ({ ...open, ...edit });

test("the 4 pt slop is the Mac's", () => {
  assert.equal(CLICK_SLOP, 4);
  const swift = fs.readFileSync(new URL("../../../NotchBuddy/Sources/App/IslandOutsideClick.swift", import.meta.url), "utf8");
  assert.equal(Number(/static let clickSlop: CGFloat = ([0-9.]+)/.exec(swift)?.[1]), CLICK_SLOP);
});

test("an open island with nothing waiting folds on a click outside; every reason to stay keeps it", () => {
  assert.equal(shouldFold(open), true);
  assert.equal(shouldFold(withOnly({ expanded: false })), false, "a compact or hidden island is never folded by a click");
  assert.equal(shouldFold(withOnly({ pinned: true })), false);
  assert.equal(shouldFold(withOnly({ held: true })), false);
  assert.equal(shouldFold(withOnly({ typing: true })), false);
  assert.equal(shouldFold(withOnly({ pointerInIsland: true })), false);
  assert.equal(shouldFold(withOnly({ busy: true })), false);
  const reasons = [{ pinned: true }, { held: true }, { typing: true }, { pointerInIsland: true }, { busy: true }];
  reasons.forEach((a, i) => reasons.slice(i + 1).forEach((b) => assert.equal(shouldFold(withOnly({ ...a, ...b })), false, `two reasons to stay (${i})`)));
});

test("a click is a press and a release within 4 px; a drag is not", () => {
  const t = new ClickTracker();
  t.down(100, 100);
  assert.equal(t.up(102, 101), true, "2 px apart is a click");
  t.down(100, 100);
  assert.equal(t.up(100, 120), false, "dragged 20 px (a file taken from Explorer, a window moved) is not a click");
  assert.equal(t.up(100, 100), false, "a release with no press seen is not a click, and the press is forgotten after each release");
  t.down(0, 0);
  assert.equal(t.up(3, 2), true, "3.6 px is still a click");
  t.down(0, 0);
  t.reset();
  assert.equal(t.up(0, 0), false, "a reset forgets the press");
  t.down(0, 0);
  assert.equal(t.up(NaN, 0), false, "a point that is not a number is not a click");
});

test("the glue folds on the release of a click, deciding by what was true at the press", () => {
  let folds = 0, ctx = open;
  const seen = [];
  const oc = new OutsideClick((e) => (seen.push(e), ctx), () => folds++);
  const press = (x, y, own = false) => oc.onButton({ down: true, x, y, own });
  const release = (x, y) => oc.onButton({ down: false, x, y, own: false });
  press(500, 300); release(501, 300);
  assert.equal(folds, 1, "a click outside folds");
  press(500, 300); release(500, 340);
  assert.equal(folds, 1, "a drag does not");
  release(500, 300);
  assert.equal(folds, 1, "a release with no press does not");
  ctx = withOnly({ typing: true });
  press(500, 300);
  ctx = open;                       // the press took the keyboard away from the chat before the release
  release(500, 300);
  assert.equal(folds, 1, "what was true at the press decides, not what is true at the release");
  press(500, 300); oc.reset(); release(500, 300);
  assert.equal(folds, 1, "a reset forgets a press in flight");
  press(10, 20, true);
  assert.deepEqual(seen.at(-1), { down: true, x: 10, y: 20, own: true }, "the context is asked with the whole event, so it can see the point and whether it is the app's own window");
});
