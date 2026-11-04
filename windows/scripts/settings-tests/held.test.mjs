// The Cat page's held slider (Task 6, part 2, B11): while a slider is dragged its value stays on screen and in the block it saves; an island change that arrives meanwhile is
// kept in every field the drag did not move; at release the block is reconciled with the latest settings. Pure: reconcile() in held.ts, replayed here.
import test from "node:test";
import assert from "node:assert/strict";
import { reconcile, hold, released } from "../../src/settings/held.ts";
import { defaultCatBlock } from "../../src/cat/display.ts";

const base = defaultCatBlock();
const size = base.desktop.size === "small" ? "large" : "small";
const dragged = { ...base, desktop: { ...base.desktop, size } };
const islandOutfit = { ...base, outfit: base.outfit === "none" ? "auto" : "none" };

test("reconcile: with no slider held, the window's block is what the page shows", () => {
  assert.deepEqual(reconcile(null, islandOutfit), islandOutfit);
});

test("reconcile: an island change to another field during a drag is shown and kept; the dragged field keeps the drag's value", () => {
  const out = reconcile({ base, value: dragged }, islandOutfit);
  assert.equal(out.desktop.size, size, "the drag's value stays");
  assert.equal(out.outfit, islandOutfit.outfit, "the island's change is not shadowed by the block the drag began from");
});

test("reconcile: an island change inside the same object as the drag is kept in the leaves the drag did not move", () => {
  const islandOn = { ...base, desktop: { ...base.desktop, on: !base.desktop.on } };
  const out = reconcile({ base, value: dragged }, islandOn);
  assert.equal(out.desktop.size, size);
  assert.equal(out.desktop.on, islandOn.desktop.on, "desktop.on is the island's, not the value the drag began from");
});

test("reconcile: an island change to the very field being dragged loses to the drag until release", () => {
  const third = ["small", "medium", "large"].find((x) => x !== base.desktop.size && x !== size);
  const islandSize = { ...base, desktop: { ...base.desktop, size: third } };
  const out = reconcile({ base, value: dragged }, islandSize);
  assert.equal(out.desktop.size, size, "the drag's value stays on screen until the slider lets go");
});

test("reconcile at release: the saved block is the drag's value over the latest settings", () => {
  assert.deepEqual(reconcile({ base, value: dragged }, base), dragged, "no island change: the drag's block");
  const out = reconcile({ base, value: dragged }, islandOutfit);
  assert.deepEqual(out, { ...islandOutfit, desktop: dragged.desktop }, "a change made by the island meanwhile is kept");
});

test("reconcile: a discrete change (no drag) saves exactly the block it was given", () => {
  assert.deepEqual(reconcile({ base: islandOutfit, value: { ...islandOutfit, outfit: base.outfit } }, islandOutfit), { ...islandOutfit, outfit: base.outfit });
});

// The review's G-N11: `base` stays the block the drag began from, so a second island change to a field the first island change already touched looked "moved by the drag"
// and was lost at release. `hold` carries the island's changes into `base` for every field the drag did not move.
const outfitA = { ...base, outfit: "none" === base.outfit ? "auto" : "none" };
const outfitB = { ...base, outfit: "snow" };

test("hold: two successive island changes to the same field during one drag both survive to the release", () => {
  const sizes = ["small", "medium", "large"].filter((x) => x !== base.desktop.size);
  // The drag begins: the page puts the first value.
  let state = hold(null, base, { ...base, desktop: { ...base.desktop, size: sizes[0] } });
  // The island changes the outfit; the page shows it, and the drag goes on from what the page shows.
  const shown = reconcile(state, outfitA);
  assert.equal(shown.outfit, outfitA.outfit);
  state = hold(state, outfitA, { ...shown, desktop: { ...shown.desktop, size: sizes[1] } });
  // The island changes the outfit again, to a third value.
  const shownAgain = reconcile(state, outfitB);
  assert.equal(shownAgain.outfit, "snow", "the page shows the island's latest outfit");
  // The slider lets go.
  const saved = released(state, outfitB, { ...shownAgain, desktop: { ...shownAgain.desktop, size: sizes[1] } });
  assert.equal(saved.outfit, "snow", "the island's second change is not lost");
  assert.equal(saved.desktop.size, sizes[1], "the drag's value is saved");
});

test("hold: the field the drag moved still wins over the island's change until release, however many events come", () => {
  const sizes = ["small", "medium", "large"].filter((x) => x !== base.desktop.size);
  let state = hold(null, base, { ...base, desktop: { ...base.desktop, size: sizes[0] } });
  const islandSize = { ...base, desktop: { ...base.desktop, size: sizes[1] } };
  state = hold(state, islandSize, reconcile(state, islandSize));
  assert.equal(reconcile(state, islandSize).desktop.size, sizes[0], "the drag's value stays");
  assert.equal(released(state, islandSize, reconcile(state, islandSize)).desktop.size, sizes[0]);
});

test("hold and released with no drag begun: the block is the latest one with the value laid over it", () => {
  assert.deepEqual(released(null, outfitA, outfitA), outfitA);
  assert.deepEqual(hold(null, outfitA, outfitB), { base: outfitA, value: outfitB });
});
