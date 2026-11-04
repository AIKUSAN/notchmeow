import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { desktopAlert } from "../../src/cat/desktop.ts";

// An incoming transfer offer is an alert to the desktop cat (docs/CAT-CONTRACT.md: `transferOffer` in desktopAlert, G2-0). The fixture's `offerCases` replay here; `alertCases` are untouched.
const fx = JSON.parse(fs.readFileSync(new URL("../../../tests/fixtures/cat/desktop-cases.json", import.meta.url), "utf8"));
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");

test("every offerCase of the cat contract", () => {
  assert.ok(fx.offerCases.length >= 5, "the fixture has its rows");
  for (const c of fx.offerCases) assert.equal(desktopAlert(c.input), c.out, c.name);
});

test("the old alertCases still hold, and a flag counts only when it is exactly true", () => {
  for (const c of fx.alertCases) assert.equal(desktopAlert(c.input), c.out, c.name);
  for (const v of [1, "true", [], {}, null, undefined, 0]) assert.equal(desktopAlert({ transferOffer: v }), false, String(v));
  assert.equal(desktopAlert({ transferOffer: true }), true);
});

test("the island passes the pending offer to the desktop cat and to the cats' sleep, and State says when one waits", () => {
  assert.match(source("island/desktop.ts"), /desktopAlert\(\{ approval: State\.attentionNeeded, fileCatch: State\.fileCatch\(\), transferOffer: State\.linkOfferPending \}\)/);
  assert.match(source("island/island.ts"), /blocked: \(\) => State\.attentionNeeded \|\| State\.linkOfferPending,/);
  assert.match(source("core/state.ts"), /get linkOfferPending\(\): boolean \{\s*return this\.link\.offerPending;\s*\}/);
});
