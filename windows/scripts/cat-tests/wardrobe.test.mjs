import test from "node:test";
import assert from "node:assert/strict";
import {
  DEFAULT_OUTFIT, OUTFIT_DRAWN, OUTFIT_GROUPS, OUTFIT_IDS, OUTFIT_NAMES, OUTFIT_ROLES, autoOutfitFor, cleanWardrobeSettings, easterOf, outfitIdOf, outfitWorn, resolveOutfit,
} from "../../src/cat/wardrobe.ts";
import { load, same } from "./util.mjs";

// The wardrobe's rules, replayed from tests/fixtures/cat/wardrobe-cases.json (I-0), and the facts the contract's own tests check.
const fx = load("wardrobe-cases.json");

test("the frozen values are the fixture's: 18 IDs in the grid's order, 16 of them drawn, five rows, the names and the roles", () => {
  assert.deepEqual([...OUTFIT_IDS], fx.ids);
  assert.deepEqual([...OUTFIT_DRAWN], fx.drawn);
  assert.deepEqual(OUTFIT_IDS.slice(2), OUTFIT_DRAWN);
  assert.deepEqual(OUTFIT_GROUPS, fx.groups);
  assert.deepEqual(OUTFIT_GROUPS.flatMap((g) => g.ids), [...OUTFIT_IDS], "the groups hold every ID once, in the order of the IDs");
  assert.deepEqual(OUTFIT_NAMES, fx.names);
  assert.deepEqual(Object.keys(OUTFIT_NAMES), [...OUTFIT_IDS]);
  assert.equal(DEFAULT_OUTFIT, fx.defaultOutfit);
  assert.deepEqual([...OUTFIT_ROLES], fx.roles);
  assert.ok(OUTFIT_IDS.every((id) => /^[a-z]+$/.test(id)), "lowercase letters only");
});

test("a stored outfit: one of the 18 exactly as written, anything else is auto (the fixture's cases)", () => {
  assert.ok(fx.clean.length >= 38);
  for (const c of fx.clean) assert.equal(outfitIdOf(c.input), c.out, c.name);
  for (const c of fx.settings) same(cleanWardrobeSettings(c.input), c.out, c.name);
  assert.deepEqual(cleanWardrobeSettings({ character: "momo", outfit: "crown", desktop: { on: true } }), { outfit: "crown" }, "only its own key is read");
  for (const v of [undefined, () => "bow", NaN, Symbol.iterator.description]) assert.equal(outfitIdOf(v), "auto", String(v));
});

test("Easter and Auto: every row of the fixture, the windows walked with the calendar, and the dates that are not dates", () => {
  for (const c of fx.easter) assert.deepEqual(easterOf(c.year), c.out, String(c.year));
  for (const c of fx.auto) assert.equal(autoOutfitFor(c.y, c.m, c.d), c.out, `${c.y}-${c.m}-${c.d}`);
  for (const w of fx.easterWindows) {
    assert.deepEqual(easterOf(w.year), w.easter, String(w.year));
    for (const d of w.days) assert.equal(autoOutfitFor(d.y, d.m, d.d), d.out, `${w.year} Easter ${d.k}`);
  }
  for (const c of fx.resolve) assert.equal(resolveOutfit(c.id, c.y, c.m, c.d), c.out, `${c.id} ${c.y}-${c.m}-${c.d}`);
  for (const id of OUTFIT_IDS) assert.notEqual(resolveOutfit(id, 2025, 7, 1), "auto", "resolved is never auto");
  assert.equal(autoOutfitFor(2024, 1, 1.5), "none");
  assert.equal(autoOutfitFor(undefined, undefined, undefined), "none");
});

test("who wears it: the big-cat role only, the fixture's rows", () => {
  for (const c of fx.worn) assert.equal(outfitWorn(c.role), c.out, JSON.stringify(c.role));
  assert.equal(outfitWorn("big"), true);
  for (const role of ["small", "kitten", "Big", 28, null, undefined]) assert.equal(outfitWorn(role), false, String(role));
});
