import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { State } from "../../src/core/state.ts";
import { WardrobeClock, msToNextMidnight } from "../../src/island/wardrobe.ts";
import { cleanCatBlock, withOutfit } from "../../src/cat/display.ts";
import { storedFor } from "../../src/cat/wardrobeui.ts";

// Auto's one-shot (sub-project I): one timer, only while the stored choice is auto, re-resolved at the next local midnight and after a long sleep, never polled.
const source = (rel) => fs.readFileSync(new URL(`../../src/${rel}`, import.meta.url), "utf8");
const HOUR = 3_600_000;

/** A local clock and a timer queue the test turns by hand, and an island that records what it is told. */
function world(choice, start) {
  const w = { t: start.getTime(), choice, timers: new Map(), id: 1, sets: 0, clears: 0, applied: [] };
  const env = {
    now: () => new Date(w.t), choice: () => w.choice,
    set: (fn, ms) => { const id = w.id++; w.sets++; w.timers.set(id, { fn, at: w.t + ms }); return id; },
    clear: (id) => { w.clears++; w.timers.delete(id); },
    apply: (o) => w.applied.push(o),
  };
  w.advance = (ms) => {
    const end = w.t + ms;
    for (;;) {
      const due = [...w.timers.entries()].filter(([, x]) => x.at <= end).sort((a, b) => a[1].at - b[1].at)[0];
      if (!due) break;
      w.t = due[1].at; w.timers.delete(due[0]); due[1].fn();
    }
    w.t = end;
  };
  return { w, clock: new WardrobeClock(env) };
}

test("the next local midnight is counted by the calendar: 0:00 of the next date, never under a second away", () => {
  for (const d of [new Date(2025, 5, 1, 12, 0, 0), new Date(2025, 11, 31, 23, 59, 59, 500), new Date(2024, 1, 29, 0, 0, 0, 0), new Date(2025, 0, 1, 0, 0, 0, 1)]) {
    const at = new Date(d.getTime() + msToNextMidnight(d));
    assert.deepEqual([at.getHours(), at.getMinutes(), at.getSeconds()], [0, 0, 0], d.toString());
    assert.ok(msToNextMidnight(d) >= 1000);
  }
  assert.equal(msToNextMidnight(new Date(2025, 5, 1, 12, 0, 0)), 12 * HOUR);
  assert.equal(msToNextMidnight(new Date(2025, 5, 1, 23, 59, 59, 999)), 1000, "a timer that fires a moment early cannot spin");
  assert.equal(msToNextMidnight(new Date(NaN)), HOUR, "a bad clock is an hour, not NaN");
});

test("a day with a daylight-saving change is 23 or 25 hours long, and the timer follows the calendar", () => {
  const old = process.env.TZ;
  try {
    process.env.TZ = "America/New_York";
    assert.equal(msToNextMidnight(new Date(2025, 2, 9, 0, 0, 0)), 23 * HOUR, "spring forward");
    assert.equal(msToNextMidnight(new Date(2025, 10, 2, 0, 0, 0)), 25 * HOUR, "fall back");
    assert.equal(msToNextMidnight(new Date(2025, 2, 9, 12, 0, 0)), 12 * HOUR, "after the change the rest of the day is as long as it reads");
    assert.equal(msToNextMidnight(new Date(2025, 2, 9, 0, 30, 0)), 23 * HOUR - 30 * 60_000, "before it, an hour is missing");
    process.env.TZ = "Pacific/Auckland";
    const d = new Date(2025, 8, 28, 1, 0, 0), at = new Date(d.getTime() + msToNextMidnight(d));
    assert.deepEqual([at.getDate(), at.getHours()], [29, 0]);
  } finally { if (old === undefined) delete process.env.TZ; else process.env.TZ = old; }
});

test("auto: the outfit for today is applied once, one timer is armed, and it fires at midnight and applies the next day's outfit", () => {
  const { w, clock } = world("auto", new Date(2025, 11, 25, 12, 0, 0));
  clock.sync();
  assert.deepEqual(w.applied, ["santahat"]);
  assert.equal(w.timers.size, 1, "one timer");
  w.advance(14 * HOUR); // 02:00 on Dec 26: still Santa
  assert.deepEqual(w.applied, ["santahat"], "the same outfit is not applied twice");
  assert.equal(w.timers.size, 1, "re-armed for the next midnight");
  w.advance(24 * HOUR); // 02:00 on Dec 27
  assert.deepEqual(w.applied, ["santahat", "none"]);
  assert.equal(clock.outfit, "none");
  assert.equal(w.timers.size, 1);
});

test("the new year's midnight, an Easter weekend and a launch on a day with no outfit", () => {
  const nye = world("auto", new Date(2025, 11, 31, 23, 0, 0));
  nye.clock.sync();
  assert.deepEqual(nye.w.applied, ["partyhat"]);
  nye.w.advance(2 * HOUR);
  assert.deepEqual(nye.w.applied, ["partyhat"], "Jan 1 is still the party hat");
  const easter = world("auto", new Date(2025, 3, 17, 12, 0, 0)); // Maundy Thursday: Easter is Apr 20, Good Friday Apr 18
  easter.clock.sync();
  assert.deepEqual(easter.w.applied, ["none"]);
  easter.w.advance(13 * HOUR);
  assert.deepEqual(easter.w.applied, ["none", "bunnyears"]);
  const plain = world("auto", new Date(2025, 4, 5, 9, 0, 0));
  plain.clock.sync();
  assert.deepEqual(plain.w.applied, ["none"], "none is applied at launch too, so the island knows");
});

test("a timer that fires late, after a long sleep, recomputes from the date then", () => {
  const { w, clock } = world("auto", new Date(2025, 5, 10, 22, 0, 0));
  clock.sync();
  assert.deepEqual(w.applied, ["none"]);
  w.advance(20 * 24 * HOUR); // the computer slept for 20 days: it is Jun 30 now
  assert.deepEqual(w.applied, ["none", "sunglasses"]);
  assert.equal(w.timers.size, 1);
});

test("an explicit outfit or none needs no timer: choosing one cancels it, choosing auto again arms it, and nothing is ever polled", () => {
  const { w, clock } = world("auto", new Date(2025, 11, 25, 12, 0, 0));
  clock.sync();
  assert.equal(w.timers.size, 1);
  w.choice = "crown"; clock.sync();
  assert.equal(w.timers.size, 0, "an explicit outfit: no timer");
  assert.deepEqual(w.applied, ["santahat", "crown"]);
  w.advance(10 * 24 * HOUR);
  assert.deepEqual(w.applied, ["santahat", "crown"], "nothing fires");
  w.choice = "none"; clock.sync();
  assert.equal(w.timers.size, 0);
  assert.deepEqual(w.applied.slice(-1), ["none"]);
  w.choice = "auto"; clock.sync();
  assert.equal(w.timers.size, 1);
  const sets = w.sets;
  w.choice = "auto"; clock.sync(); clock.sync();
  assert.equal(w.timers.size, 1, "a sync never leaves two timers");
  assert.equal(w.sets, sets + 2);
});

test("a click in Settings reaches the clock: an explicit outfit clears Auto's armed timer, and choosing Auto arms one again", () => {
  // The card's click stores the tile's ID through withOutfit; the block is saved, settings-changed reaches the island, applySettings syncs the clock with what it stores.
  let block = cleanCatBlock({ outfit: "auto" });
  const { w, clock } = world(block.outfit, new Date(2025, 11, 25, 12, 0, 0));
  clock.sync();
  assert.equal(w.timers.size, 1, "Auto is armed");
  block = withOutfit(block, storedFor("crown")); w.choice = block.outfit; clock.sync();
  assert.equal(w.timers.size, 0, "the explicit outfit cancels the timer");
  assert.deepEqual(w.applied, ["santahat", "crown"]);
  block = withOutfit(block, storedFor("auto")); w.choice = block.outfit; clock.sync();
  assert.equal(w.timers.size, 1, "choosing Auto arms one again");
  assert.deepEqual(w.applied, ["santahat", "crown", "santahat"]);
  // The path the click takes, pinned by source: the card's put is the Cat section's change, which hands the block to the window's put, which saves it when final.
  assert.match(source("settings/cat.ts"), /wardrobeSection\(\{ block: \(\) => host\.cat\(\), put: \(next, final\) => change\(next, final\) \}/);
  assert.match(source("settings/cat.ts"), /const change = \(next: CatSettings \| CatBlock, final = true\) => \{\s*host\.put\(withCatSettings\(host\.cat\(\), next\), final\);/);
  assert.match(source("settings/app.ts"), /put: \(next, final\) => \{\s*const latest = ctx\.settings\(\)\.cat;\s*if \(!final\) \{ held = hold\(held, latest, next\); return; \}\s*const block = released\(held, latest, next\);\s*held = null;\s*void ctx\.save\(\{ \.\.\.ctx\.settings\(\), cat: block \}\);/);
  assert.match(source("main.ts"), /onEvent<Settings>\("settings-changed", \(s\) => \{[\s\S]*?island\.applySettings\(\);/);
});

test("a stored value that is not an outfit is auto, and a bad clock never throws", () => {
  for (const bad of [undefined, null, 7, "Crown", "", {}, ["bow"]]) {
    const { w, clock } = world(bad, new Date(2025, 11, 25, 12, 0, 0));
    clock.sync();
    assert.deepEqual(w.applied, ["santahat"], String(bad));
    assert.equal(w.timers.size, 1);
  }
  const { w, clock } = world("auto", new Date(NaN));
  assert.doesNotThrow(() => clock.sync());
  assert.deepEqual(w.applied, ["none"]);
});

test("the island keeps it in State after each sync, wears nothing before the first one, and the clock is built once with real timers", () => {
  assert.equal(State.outfit, "none");
  const island = source("island/island.ts"), state = source("core/state.ts");
  assert.match(island, /private wardrobe = new WardrobeClock\(\{\s*now: \(\) => new Date\(\),\s*choice: \(\) => State\.settings\.cat\.outfit,\s*set: \(fn, ms\) => window\.setTimeout\(fn, ms\),\s*clear: \(id\) => window\.clearTimeout\(id\),\s*apply: \(outfit\) => \{ State\.outfit = outfit; State\.notify\(\); \},\s*\}\);/);
  assert.match(island, /State\.settings\.cat = block;\s*this\.wardrobe\.sync\(\);\s*State\.notify\(\);/);
  assert.match(state, /outfit: OutfitId = "none";/);
  assert.equal((island.match(/new WardrobeClock\(/g) || []).length, 1);
  assert.ok(!/setInterval/.test(source("island/wardrobe.ts")), "nothing polls");
});
