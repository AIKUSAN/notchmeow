import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import * as R from "../../src/shelf/rules.ts";

// The shelf contract (G1-0), replayed from tests/fixtures/shelf/. `reference.py` decides when this file and a fixture disagree.
const fx = (name) => JSON.parse(fs.readFileSync(new URL(`../../../tests/fixtures/shelf/${name}`, import.meta.url), "utf8"));
const cases = fx("shelf-cases.json"), zones = fx("zone-cases.json");
const json = (v) => JSON.parse(JSON.stringify(v));

test("the constants are the fixture's", () => {
  assert.deepEqual([R.SHELF_MAX, R.ID_RE.source.replace(/^\^|\$$/g, ""), R.NAME_MAX, R.LINK_MAX, R.NUMBER_MAX], [cases.max, cases.idPattern, cases.nameMax, cases.linkMax, cases.numberMax]);
});

test("zoneAt replays every row of zone-cases.json (a missing key stands for a value JSON cannot hold)", () => {
  assert.ok(zones.cases.length >= 30);
  for (const c of zones.cases) assert.equal(R.zoneAt(c.x, c.width), c.out, c.name);
});

test("zoneAt: the centre line is Ask, the rest of the right half is Shelf, outside is null, and no input throws", () => {
  assert.equal(R.zoneAt(300, 600), "ask");
  assert.equal(R.zoneAt(300.0001, 600), "shelf");
  assert.equal(R.zoneAt(-0.0001, 600), null);
  assert.equal(R.zoneAt(600.0001, 600), null);
  for (const bad of [undefined, null, true, "5", [], {}, NaN, Infinity, 1e300]) {
    assert.equal(R.zoneAt(bad, 600), null);
    assert.equal(R.zoneAt(5, bad), null);
  }
});

test("shelfClean replays every cleanCases row, in the contract's field order", () => {
  assert.ok(cases.cleanCases.length >= 100);
  for (const c of cases.cleanCases) assert.deepEqual(json(R.shelfClean(c.raw)), c.out, c.name);
  const [one] = R.shelfClean({ items: [{ id: "a", name: "f.txt", size: 1, folder: false, copy: false, link: "/p/a", addedAt: 5, extra: 1 }] });
  assert.deepEqual(Object.keys(one), ["id", "name", "size", "folder", "copy", "link", "addedAt"]);
});

test("shelfAdd replays every addCases row", () => {
  assert.ok(cases.addCases.length >= 25);
  for (const c of cases.addCases) assert.deepEqual(json(R.shelfAdd(c.items, c.incoming)), c.out, c.name);
});

test("readShelf replays every parseCases row (text, or hex when the bytes are not UTF-8)", () => {
  assert.ok(cases.parseCases.length >= 15);
  for (const c of cases.parseCases) {
    const bytes = c.text !== undefined ? new TextEncoder().encode(c.text) : Uint8Array.from(Buffer.from(c.hex, "hex"));
    assert.deepEqual(json(R.readShelf(bytes)), c.out, c.name);
  }
});

test("a drop on a full shelf refuses the extras and removes nothing; a re-dropped file says duplicate even then", () => {
  const mk = (n) => ({ id: `i${n}`, name: `f${n}.txt`, size: 1, folder: false, copy: false, link: `/p/${n}`, addedAt: 1000 + n });
  const full = Array.from({ length: R.SHELF_MAX }, (_, n) => mk(n));
  const res = R.shelfAdd(full, [mk(5), mk(99), { nope: 1 }]);
  assert.deepEqual(res.results, ["duplicate", "full", "invalid"]);
  assert.equal(res.items.length, R.SHELF_MAX);
  assert.deepEqual(new Set(res.items.map((i) => i.id)), new Set(full.map((i) => i.id)));
});

test("a hostile shelf never throws and a clean one stays clean (the rules are idempotent)", () => {
  for (const hostile of [undefined, null, 5, "x", [], { items: 5 }, { items: [null, 1, "a", [], { id: 5 }] }, { items: Array.from({ length: 300 }, (_, n) => ({ id: `a${n}`, name: "n", link: `/${n}`, addedAt: n })) }]) {
    const once = R.shelfClean(hostile);
    assert.deepEqual(R.shelfClean({ items: once }), once);
    assert.ok(once.length <= R.SHELF_MAX);
  }
  assert.equal(R.shelfClean({ items: Array.from({ length: 300 }, (_, n) => ({ id: `a${n}`, name: "n", link: `/${n}`, addedAt: n })) })[0].addedAt, 299, "300 items keep the 30 newest");
});

test("minus zero is the number 0 (JSON.parse gives -0; Object.is tells them apart where a JSON round trip would not)", () => {
  const [it] = R.readShelf(new TextEncoder().encode('{"items":[{"id":"a","name":"f.txt","size":-0,"copy":true,"addedAt":-0.0}]}'));
  assert.ok(Object.is(it.size, 0) && Object.is(it.addedAt, 0));
});
